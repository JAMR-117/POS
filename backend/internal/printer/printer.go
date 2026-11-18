package printer

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

type PrintRequest struct {
	PrinterType    string `json:"printer_type"` // "windows_spooler" | "network"
	PrinterName    string `json:"printer_name"`
	Address        string `json:"address"`
	Port           int    `json:"port"`
	RawBytesBase64 string `json:"raw_bytes_base64"`
	PlainText      string `json:"plain_text"`
}

type PrintResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type DeviceStatusResponse struct {
	Success       bool     `json:"success"`
	Printers      []string `json:"printers"`
	SerialPorts   []string `json:"serial_ports"`
	ServiceStatus string   `json:"service_status"`
	Timestamp     string   `json:"timestamp"`
}

// Windows winspool.drv lazy binding para impresión RAW sin diálogos
var (
	winspool             *syscall.LazyDLL
	procOpenPrinter      *syscall.LazyProc
	procStartDocPrinter  *syscall.LazyProc
	procStartPagePrinter *syscall.LazyProc
	procWritePrinter     *syscall.LazyProc
	procEndPagePrinter   *syscall.LazyProc
	procEndDocPrinter    *syscall.LazyProc
	procClosePrinter     *syscall.LazyProc
)

func init() {
	if runtime.GOOS == "windows" {
		winspool = syscall.NewLazyDLL("winspool.drv")
		procOpenPrinter = winspool.NewProc("OpenPrinterW")
		procStartDocPrinter = winspool.NewProc("StartDocPrinterW")
		procStartPagePrinter = winspool.NewProc("StartPagePrinter")
		procWritePrinter = winspool.NewProc("WritePrinter")
		procEndPagePrinter = winspool.NewProc("EndPagePrinter")
		procEndDocPrinter = winspool.NewProc("EndDocPrinter")
		procClosePrinter = winspool.NewProc("ClosePrinter")
	}
}

type docInfo1 struct {
	DocName    *uint16
	OutputFile *uint16
	Datatype   *uint16
}

// GetInstalledPrinters lista las impresoras instaladas en el SO con arquitectura multimétodo de fallback
func GetInstalledPrinters() ([]string, error) {
	if runtime.GOOS != "windows" {
		return []string{"Default Printer (Non-Windows)"}, nil
	}

	seen := make(map[string]bool)
	var printers []string

	addPrinter := func(name string) {
		name = strings.TrimSpace(name)
		if name != "" && !seen[name] {
			seen[name] = true
			printers = append(printers, name)
		}
	}

	// Método 1: PowerShell CIM Instance Win32_Printer (Más rápido y moderno en Win 10/11)
	cmd1 := exec.Command("powershell", "-NoProfile", "-Command", "Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name")
	if out, err := cmd1.Output(); err == nil && len(out) > 0 {
		for _, l := range strings.Split(string(out), "\n") {
			addPrinter(l)
		}
	}

	// Método 2: PowerShell Get-Printer estándar (si está presente PrintManagement)
	if len(printers) == 0 {
		cmd2 := exec.Command("powershell", "-NoProfile", "-Command", "Get-Printer | Select-Object -ExpandProperty Name")
		if out, err := cmd2.Output(); err == nil && len(out) > 0 {
			for _, l := range strings.Split(string(out), "\n") {
				addPrinter(l)
			}
		}
	}

	// Método 3: Registro de Windows (HKCU\Software\Microsoft\Windows NT\CurrentVersion\Devices)
	if len(printers) == 0 {
		cmd3 := exec.Command("reg", "query", `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Devices`)
		if out, err := cmd3.Output(); err == nil && len(out) > 0 {
			scanner := bufio.NewScanner(bytes.NewReader(out))
			for scanner.Scan() {
				line := strings.TrimSpace(scanner.Text())
				if strings.Contains(line, "REG_SZ") {
					parts := strings.Split(line, "REG_SZ")
					if len(parts) >= 2 {
						pName := strings.TrimSpace(parts[0])
						addPrinter(pName)
					}
				}
			}
		}
	}

	// Método 4: WMIC (Fallback legado en Windows antiguos)
	if len(printers) == 0 {
		cmd4 := exec.Command("wmic", "printer", "get", "Name", "/format:csv")
		if out, err := cmd4.Output(); err == nil && len(out) > 0 {
			for _, l := range strings.Split(string(out), "\n") {
				parts := strings.Split(strings.TrimSpace(l), ",")
				if len(parts) >= 2 {
					candidate := parts[len(parts)-1]
					if candidate != "Name" && candidate != "" {
						addPrinter(candidate)
					}
				}
			}
		}
	}

	return printers, nil
}

// GetAvailableSerialPorts detecta puertos COM físicos o emulados por USB
func GetAvailableSerialPorts() []string {
	if runtime.GOOS != "windows" {
		return []string{}
	}

	var ports []string
	seen := make(map[string]bool)

	addPort := func(p string) {
		p = strings.TrimSpace(p)
		if p != "" && !seen[p] {
			seen[p] = true
			ports = append(ports, p)
		}
	}

	// Método 1: .NET SerialPort GetPortNames
	cmd := exec.Command("powershell", "-NoProfile", "-Command", "[System.IO.Ports.SerialPort]::GetPortNames()")
	if out, err := cmd.Output(); err == nil && len(out) > 0 {
		for _, l := range strings.Split(string(out), "\n") {
			addPort(l)
		}
	}

	// Método 2: Registro de Windows SERIALCOMM
	if len(ports) == 0 {
		cmdReg := exec.Command("reg", "query", `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`)
		if out, err := cmdReg.Output(); err == nil && len(out) > 0 {
			scanner := bufio.NewScanner(bytes.NewReader(out))
			for scanner.Scan() {
				line := strings.TrimSpace(scanner.Text())
				if strings.Contains(line, "REG_SZ") {
					parts := strings.Split(line, "REG_SZ")
					if len(parts) >= 2 {
						portName := strings.TrimSpace(parts[1])
						addPort(portName)
					}
				}
			}
		}
	}

	return ports
}

// PrintRaw envía bytes a la impresora especificada
func PrintRaw(req PrintRequest) error {
	var data []byte

	if req.RawBytesBase64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(req.RawBytesBase64)
		if err != nil {
			return fmt.Errorf("error decodificando raw_bytes_base64: %w", err)
		}
		data = decoded
	} else if req.PlainText != "" {
		data = []byte(req.PlainText)
	} else {
		return fmt.Errorf("solicitud vacía: ni raw_bytes_base64 ni plain_text fueron proporcionados")
	}

	if req.PrinterType == "network" {
		port := req.Port
		if port <= 0 {
			port = 9100
		}
		if req.Address == "" {
			return fmt.Errorf("dirección IP de red no especificada")
		}
		addr := net.JoinHostPort(req.Address, fmt.Sprintf("%d", port))
		conn, err := net.DialTimeout("tcp", addr, 3*time.Second)
		if err != nil {
			return fmt.Errorf("no se pudo conectar a impresora de red (%s): %w", addr, err)
		}
		defer conn.Close()

		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
		_, err = conn.Write(data)
		if err != nil {
			return fmt.Errorf("falla al transmitir bytes a la impresora: %w", err)
		}
		return nil
	}

	// Tipo: "windows_spooler"
	if runtime.GOOS != "windows" {
		return fmt.Errorf("impresora windows_spooler solo está soportada en Windows")
	}

	if req.PrinterName == "" {
		return fmt.Errorf("nombre de impresora no especificado")
	}

	return printToWindowsSpooler(req.PrinterName, data)
}

func printToWindowsSpooler(printerName string, data []byte) error {
	if len(data) == 0 {
		return nil
	}

	pNamePtr, err := syscall.UTF16PtrFromString(printerName)
	if err != nil {
		return fmt.Errorf("nombre de impresora inválido: %w", err)
	}

	var hPrinter uintptr
	r1, _, err := procOpenPrinter.Call(
		uintptr(unsafe.Pointer(pNamePtr)),
		uintptr(unsafe.Pointer(&hPrinter)),
		0,
	)
	if r1 == 0 {
		return fmt.Errorf("OpenPrinter falló para '%s': %w", printerName, err)
	}
	defer procClosePrinter.Call(hPrinter)

	docName, _ := syscall.UTF16PtrFromString("POS Ticket Cerrajería")
	dataType, _ := syscall.UTF16PtrFromString("RAW")
	docInfo := docInfo1{
		DocName:  docName,
		Datatype: dataType,
	}

	r1, _, err = procStartDocPrinter.Call(
		hPrinter,
		1,
		uintptr(unsafe.Pointer(&docInfo)),
	)
	if r1 == 0 {
		return fmt.Errorf("StartDocPrinter falló: %w", err)
	}
	defer procEndDocPrinter.Call(hPrinter)

	procStartPagePrinter.Call(hPrinter)
	defer procEndPagePrinter.Call(hPrinter)

	var bytesWritten uint32
	r1, _, err = procWritePrinter.Call(
		hPrinter,
		uintptr(unsafe.Pointer(&data[0])),
		uintptr(len(data)),
		uintptr(unsafe.Pointer(&bytesWritten)),
	)
	if r1 == 0 {
		return fmt.Errorf("WritePrinter falló al enviar %d bytes: %w", len(data), err)
	}

	return nil
}

// Handler HTTP para los endpoints de impresión
type Handler struct{}

func NewHandler() *Handler {
	return &Handler{}
}

func (h *Handler) GetPrinters(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	printers, err := GetInstalledPrinters()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": err.Error(), "printers": []string{}})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"printers": printers, "count": len(printers)})
}

func (h *Handler) GetDevices(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	printers, _ := GetInstalledPrinters()
	ports := GetAvailableSerialPorts()

	resp := DeviceStatusResponse{
		Success:       true,
		Printers:      printers,
		SerialPorts:   ports,
		ServiceStatus: "ONLINE",
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) Print(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	var req PrintRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(PrintResponse{Success: false, Message: "Payload JSON inválido: " + err.Error()})
		return
	}

	err := PrintRaw(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(PrintResponse{Success: false, Message: err.Error()})
		return
	}

	_ = json.NewEncoder(w).Encode(PrintResponse{Success: true, Message: "Impresión despachada exitosamente."})
}
