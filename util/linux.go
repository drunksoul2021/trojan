package util

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// PortIsUse 判断端口是否占用
func PortIsUse(port int) bool {
	_, tcpError := net.DialTimeout("tcp", fmt.Sprintf(":%d", port), time.Millisecond*50)
	udpAddr, _ := net.ResolveUDPAddr("udp4", fmt.Sprintf(":%d", port))
	udpConn, udpError := net.ListenUDP("udp", udpAddr)
	if udpConn != nil {
		defer udpConn.Close()
	}
	return tcpError == nil || udpError != nil
}

// RandomPort 获取没占用的随机端口
func RandomPort() int {
	for {
		rand.New(rand.NewSource(time.Now().UnixNano()))
		newPort := rand.Intn(65536)
		if !PortIsUse(newPort) {
			return newPort
		}
	}
}

// IsExists 检测指定路径文件或者文件夹是否存在
func IsExists(path string) bool {
	_, err := os.Stat(path) //os.Stat获取文件信息
	if err != nil {
		if os.IsExist(err) {
			return true
		}
		return false
	}
	return true
}

// GetLocalIP 获取本机ipv4地址
func GetLocalIP() string {
	transport := &http.Transport{DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, "tcp4", address)
	}, TLSHandshakeTimeout: 10 * time.Second}
	client := &http.Client{Transport: transport, Timeout: 15 * time.Second}
	for _, endpoint := range []string{"https://api.ipify.org", "https://icanhazip.com"} {
		resp, err := client.Get(endpoint)
		if err != nil {
			continue
		}
		data, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		ip := strings.TrimSpace(string(data))
		if resp.StatusCode == 200 && readErr == nil && net.ParseIP(ip) != nil && net.ParseIP(ip).To4() != nil {
			return ip
		}
	}
	return ""
}

// InstallPack 安装指定名字软件
func InstallPack(name string) {
	if !CheckCommandExists(name) {
		if CheckCommandExists("yum") {
			ExecCommand("yum install -y " + name)
		} else if CheckCommandExists("apt-get") {
			ExecCommand("apt-get update")
			ExecCommand("apt-get install -y " + name)
		}
	}
}

// OpenPort applies only configured Trojan TCP rules; the web backend stays private.
func OpenPort(port int) {
	if IsExists("/usr/local/lib/trojan-manager/scripts/firewall.sh") {
		if err := ExecCommand("bash /usr/local/lib/trojan-manager/scripts/firewall.sh"); err != nil {
			fmt.Println("防火墙配置失败:", err)
		}
	}
}

// Log 实时打印指定服务日志
func Log(serviceName string, line int) {
	result, _ := LogChan(serviceName, "-n "+strconv.Itoa(line), make(chan byte))
	for line := range result {
		fmt.Println(line)
	}
}

// LogChan 指定服务实时日志, 返回chan
func LogChan(serviceName, param string, closeChan chan byte) (chan string, error) {
	cmd := exec.Command("bash", "-c", fmt.Sprintf("journalctl -f -u %s -o cat %s", serviceName, param))

	stdout, _ := cmd.StdoutPipe()

	if err := cmd.Start(); err != nil {
		fmt.Println("Error:The command is err: ", err.Error())
		return nil, err
	}
	ch := make(chan string, 100)
	stdoutScan := bufio.NewScanner(stdout)
	go func() {
		for stdoutScan.Scan() {
			select {
			case <-closeChan:
				stdout.Close()
				return
			default:
				ch <- stdoutScan.Text()
			}
		}
	}()
	return ch, nil
}
