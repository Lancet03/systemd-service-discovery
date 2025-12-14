package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	clientv3 "go.etcd.io/etcd/client/v3"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr           string
	EtcdEndpoints      []string
	KeyPrefix          string
	DefaultTTL         int64
	DefaultServicePort int
	EtcdTimeout        time.Duration
}


type ServiceRecord struct {
	ID          string `json:"id"`
	IP          string `json:"ip"`
	Port        int    `json:"port"`
	Description string `json:"description,omitempty"`
	LastSeen    string `json:"last_seen"` // RFC3339Nano
}

type RegisterRequest struct {
	ID          string `json:"id"`
	IP          string `json:"ip,omitempty"`
	Description string `json:"description,omitempty"`
}


type HeartbeatRequest struct {
	ID string `json:"id"`
}

type Server struct {
	cfg  Config
	etcd *clientv3.Client
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   cfg.EtcdEndpoints,
		DialTimeout: 3 * time.Second,
	})
	if err != nil {
		log.Fatalf("etcd client: %v", err)
	}
	defer cli.Close()

	s := &Server{cfg: cfg, etcd: cli}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/register", s.handleRegister)
	mux.HandleFunc("/heartbeat", s.handleHeartbeat)
	mux.HandleFunc("/services", s.handleServices)
	mux.HandleFunc("/services/", s.handleServiceByID) // GET/DELETE /services/{id}

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           withJSONContentType(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("discovery listening on %s", cfg.HTTPAddr)
	log.Printf("etcd endpoints: %v", cfg.EtcdEndpoints)
	log.Printf("prefix: %s (services under %s)", cfg.KeyPrefix, s.servicesPrefix())

	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("http server: %v", err)
	}
}

func loadConfig() (Config, error) {
	httpAddr := getenv("DISCOVERY_HTTP_ADDR", ":8080")

	endpointsRaw := getenv("ETCD_ENDPOINTS", "http://127.0.0.1:2379")
	endpoints := splitAndTrim(endpointsRaw, ",")

	prefix := getenv("DISCOVERY_PREFIX", "/sd")
	prefix = strings.TrimRight(prefix, "/")

	defaultTTL := getenvInt64("DISCOVERY_TTL_SECONDS", 30)
	if defaultTTL < 5 {
		return Config{}, fmt.Errorf("DISCOVERY_TTL_SECONDS too small: %d", defaultTTL)
	}

	defaultSvcPort := int(getenvInt64("DISCOVERY_DEFAULT_SERVICE_PORT", 8081))
	if defaultSvcPort <= 0 {
		return Config{}, fmt.Errorf("DISCOVERY_DEFAULT_SERVICE_PORT invalid: %d", defaultSvcPort)
	}

	timeoutMs := getenvInt64("ETCD_TIMEOUT_MS", 2000)

	return Config{
	HTTPAddr:           httpAddr,
	EtcdEndpoints:      endpoints,
	KeyPrefix:          prefix,
	DefaultTTL:         defaultTTL,
	DefaultServicePort: defaultSvcPort,
	EtcdTimeout:        time.Duration(timeoutMs) * time.Millisecond,
}, nil
}

func (s *Server) servicesPrefix() string {
	return s.cfg.KeyPrefix + "/services/"
}

func (s *Server) keyFor(id string) string {
	return s.servicesPrefix() + id
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req RegisterRequest
	if err := readJSON(r.Body, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	req.ID = strings.TrimSpace(req.ID)
	if req.ID == "" {
		writeError(w, http.StatusBadRequest, "id is required")
		return
	}

	ip := strings.TrimSpace(req.IP)
	if ip == "" {
		ip = clientIP(r) // берём из заголовков/RemoteAddr
	}

	rec := ServiceRecord{
		ID:          req.ID,
		IP:          ip,
		Port:        s.cfg.DefaultServicePort,
		Description: req.Description,
		LastSeen:    time.Now().UTC().Format(time.RFC3339Nano),
	}

	valueBytes, _ := json.Marshal(rec)
	key := s.keyFor(req.ID)

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.EtcdTimeout)
	defer cancel()

	ttl := s.cfg.DefaultTTL
	leaseResp, err := s.etcd.Grant(ctx, ttl)
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd grant lease failed: "+err.Error())
		return
	}

	_, err = s.etcd.Put(ctx, key, string(valueBytes), clientv3.WithLease(leaseResp.ID))
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd put failed: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"ok":          true,
		"id":          req.ID,
		"ip":          ip,
		"port":        s.cfg.DefaultServicePort,
		"ttl_seconds": ttl,
		"lease_id":    int64(leaseResp.ID),
	})
}

func clientIP(r *http.Request) string {
	// Если discovery стоит за reverse-proxy, клиентский IP будет в X-Forwarded-For
	xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For"))
	if xff != "" {
		parts := strings.Split(xff, ",")
		if len(parts) > 0 {
			ip := strings.TrimSpace(parts[0])
			if ip != "" {
				return ip
			}
		}
	}

	xri := strings.TrimSpace(r.Header.Get("X-Real-IP"))
	if xri != "" {
		return xri
	}

	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

func (s *Server) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req HeartbeatRequest
	if err := readJSON(r.Body, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	req.ID = strings.TrimSpace(req.ID)
	if req.ID == "" {
		writeError(w, http.StatusBadRequest, "id is required")
		return
	}

	key := s.keyFor(req.ID)

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.EtcdTimeout)
	defer cancel()

	getResp, err := s.etcd.Get(ctx, key)
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd get failed: "+err.Error())
		return
	}
	if len(getResp.Kvs) == 0 {
		// ключ мог быть автоматически удалён после истечения lease TTL 
		writeError(w, http.StatusNotFound, "service not found (expired or not registered)")
		return
	}

	kv := getResp.Kvs[0]
	leaseID := clientv3.LeaseID(kv.Lease)

	// Обновим last_seen в значении (не обязательно для TTL, но полезно для клиентов)
	var rec ServiceRecord
	if err := json.Unmarshal(kv.Value, &rec); err != nil {
		// если значение битое — перерегистрируем минимально
		rec = ServiceRecord{ID: req.ID}
	}
	rec.LastSeen = time.Now().UTC().Format(time.RFC3339Nano)

	valueBytes, _ := json.Marshal(rec)

	// Если leaseID отсутствует (0) — выдадим новый lease и перевяжем ключ
	if leaseID == 0 {
		leaseResp, gerr := s.etcd.Grant(ctx, s.cfg.DefaultTTL)
		if gerr != nil {
			writeError(w, http.StatusBadGateway, "etcd grant lease failed: "+gerr.Error())
			return
		}
		leaseID = leaseResp.ID
	}

	_, err = s.etcd.Put(ctx, key, string(valueBytes), clientv3.WithLease(leaseID))
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd put failed: "+err.Error())
		return
	}

	// Продлеваем lease точечно (KeepAliveOnce) — без постоянного стрима.
	// Lease/KeepAlive — базовый механизм liveness в etcd. 
	_, err = s.etcd.KeepAliveOnce(ctx, leaseID)
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd keepalive failed: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"ok":       true,
		"id":       req.ID,
		"lease_id": int64(leaseID),
	})
}

func (s *Server) handleServices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.EtcdTimeout)
	defer cancel()

	resp, err := s.etcd.Get(ctx, s.servicesPrefix(), clientv3.WithPrefix())
	if err != nil {
		writeError(w, http.StatusBadGateway, "etcd get prefix failed: "+err.Error())
		return
	}

	services := make([]ServiceRecord, 0, len(resp.Kvs))
	for _, kv := range resp.Kvs {
		var rec ServiceRecord
		if err := json.Unmarshal(kv.Value, &rec); err == nil && rec.ID != "" {
			services = append(services, rec)
		}
	}

	writeJSON(w, http.StatusOK, services)
}

func (s *Server) handleServiceByID(w http.ResponseWriter, r *http.Request) {
	// path: /services/{id}
	id := strings.TrimPrefix(r.URL.Path, "/services/")
	id = strings.TrimSpace(id)
	if id == "" {
		writeError(w, http.StatusBadRequest, "id is required")
		return
	}
	key := s.keyFor(id)

	switch r.Method {
	case http.MethodGet:
		ctx, cancel := context.WithTimeout(r.Context(), s.cfg.EtcdTimeout)
		defer cancel()

		resp, err := s.etcd.Get(ctx, key)
		if err != nil {
			writeError(w, http.StatusBadGateway, "etcd get failed: "+err.Error())
			return
		}
		if len(resp.Kvs) == 0 {
			writeError(w, http.StatusNotFound, "not found")
			return
		}

		var rec ServiceRecord
		if err := json.Unmarshal(resp.Kvs[0].Value, &rec); err != nil {
			writeError(w, http.StatusInternalServerError, "stored json is invalid")
			return
		}
		writeJSON(w, http.StatusOK, rec)

	case http.MethodDelete:
		ctx, cancel := context.WithTimeout(r.Context(), s.cfg.EtcdTimeout)
		defer cancel()

		// опционально: сначала читаем lease и ревокаем (ускоряет удаление)
		resp, err := s.etcd.Get(ctx, key)
		if err == nil && len(resp.Kvs) > 0 {
			leaseID := clientv3.LeaseID(resp.Kvs[0].Lease)
			if leaseID != 0 {
				_, _ = s.etcd.Revoke(ctx, leaseID)
			}
		}
		_, err = s.etcd.Delete(ctx, key)
		if err != nil {
			writeError(w, http.StatusBadGateway, "etcd delete failed: "+err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "id": id})

	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

func withJSONContentType(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// мы всегда отвечаем JSON
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		next.ServeHTTP(w, r)
	})
}

func readJSON(body io.ReadCloser, v any) error {
	defer body.Close()
	dec := json.NewDecoder(body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]any{"ok": false, "error": msg})
}

func getenv(key, def string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	return v
}

func getenvInt64(key string, def int64) int64 {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return def
	}
	return n
}

func splitAndTrim(s, sep string) []string {
	parts := strings.Split(s, sep)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
