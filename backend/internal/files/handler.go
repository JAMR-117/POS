package files

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

type Handler struct{}

func NewHandler() *Handler {
	return &Handler{}
}

type SavePdfRequest struct {
	Directory string `json:"directory"`
	Filename  string `json:"filename"`
	PdfBase64 string `json:"pdf_base64"`
}

type SavePdfResponse struct {
	Success bool   `json:"success"`
	Path    string `json:"path"`
	Error   string `json:"error,omitempty"`
}

func (h *Handler) SavePdf(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	var req SavePdfRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(SavePdfResponse{Success: false, Error: "Payload JSON inválido: " + err.Error()})
		return
	}

	dir := req.Directory
	if dir == "" {
		dir = `C:\POS\Cotizaciones`
	}

	if err := os.MkdirAll(dir, 0755); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(SavePdfResponse{Success: false, Error: "Error creando carpeta: " + err.Error()})
		return
	}

	filename := req.Filename
	if filename == "" {
		filename = fmt.Sprintf("Cotizacion_%d.pdf", time.Now().Unix())
	}
	fullPath := filepath.Join(dir, filename)

	bytes, err := base64.StdEncoding.DecodeString(req.PdfBase64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(SavePdfResponse{Success: false, Error: "Error decodificando base64: " + err.Error()})
		return
	}

	if err := os.WriteFile(fullPath, bytes, 0644); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(SavePdfResponse{Success: false, Error: "Error guardando archivo: " + err.Error()})
		return
	}

	_ = json.NewEncoder(w).Encode(SavePdfResponse{
		Success: true,
		Path:    fullPath,
	})
}

type OpenFileRequest struct {
	Path string `json:"path"`
}

func (h *Handler) OpenFile(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	var req OpenFileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": err.Error()})
		return
	}

	targetPath := req.Path
	if targetPath == "" {
		targetPath = `C:\POS\Cotizaciones`
	}

	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		if fi, err := os.Stat(targetPath); err == nil && fi.IsDir() {
			cmd = exec.Command("explorer.exe", targetPath)
		} else {
			cmd = exec.Command("cmd.exe", "/c", "start", "", targetPath)
		}
	} else {
		cmd = exec.Command("xdg-open", targetPath)
	}

	if err := cmd.Start(); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": err.Error()})
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]any{"success": true, "path": targetPath})
}

type ClipboardImageRequest struct {
	ImageBase64 string `json:"image_base64"`
}

func (h *Handler) CopyImageToClipboard(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	var req ClipboardImageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": err.Error()})
		return
	}

	imgBytes, err := base64.StdEncoding.DecodeString(req.ImageBase64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": "Base64 inválido: " + err.Error()})
		return
	}

	tempDir := os.TempDir()
	tempFile := filepath.Join(tempDir, fmt.Sprintf("pos_clipboard_%d.png", time.Now().UnixNano()))
	if err := os.WriteFile(tempFile, imgBytes, 0644); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": "Error creando imagen temporal: " + err.Error()})
		return
	}

	go func(f string) {
		time.Sleep(15 * time.Second)
		_ = os.Remove(f)
	}(tempFile)

	if runtime.GOOS == "windows" {
		psScript := fmt.Sprintf(`Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; [System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile('%s'))`, tempFile)
		cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", psScript)
		out, err := cmd.CombinedOutput()
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": fmt.Sprintf("Error copiando al portapapeles: %v (%s)", err, string(out))})
			return
		}
	}

	_ = json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"message": "Imagen copiada exitosamente al portapapeles de Windows",
	})
}
