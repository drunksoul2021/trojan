package util

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

func systemctlBase(name, operate string) (string, error) {
	out, err := exec.Command("systemctl", operate, name).CombinedOutput()
	return string(out), err
}

// SystemctlStart 服务启动
func SystemctlStart(name string) {
	if _, err := systemctlBase(name, "start"); err != nil {
		fmt.Println(Red(fmt.Sprintf("启动%s失败!", name)))
	} else {
		fmt.Println(Green(fmt.Sprintf("启动%s成功!", name)))
	}
}

// SystemctlStop 服务停止
func SystemctlStop(name string) {
	if _, err := systemctlBase(name, "stop"); err != nil {
		fmt.Println(Red(fmt.Sprintf("停止%s失败!", name)))
	} else {
		fmt.Println(Green(fmt.Sprintf("停止%s成功!", name)))
	}
}

// SystemctlRestart 服务重启
func SystemctlRestart(name string) {
	if _, err := systemctlBase(name, "restart"); err != nil {
		fmt.Println(Red(fmt.Sprintf("重启%s失败!", name)))
	} else {
		fmt.Println(Green(fmt.Sprintf("重启%s成功!", name)))
	}
}

// SystemctlEnable 服务设置开机自启
func SystemctlEnable(name string) {
	if _, err := systemctlBase(name, "enable"); err != nil {
		fmt.Println(Red(fmt.Sprintf("设置%s开机自启失败!", name)))
	}
}

// SystemctlStatus 服务状态查看
func SystemctlStatus(name string) string {
	out, _ := systemctlBase(name, "status")
	return out
}

// CheckCommandExists 检查命令是否存在
func CheckCommandExists(command string) bool {
	if _, err := exec.LookPath(command); err != nil {
		return false
	}
	return true
}

// RunWebShell 运行网上的脚本
func RunWebShell(webShellPath string) {
	if !strings.HasPrefix(webShellPath, "http") && !strings.HasPrefix(webShellPath, "https") {
		fmt.Printf("shell path must start with http or https!")
		return
	}
	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(webShellPath)
	if err != nil {
		fmt.Println(err.Error())
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Println("下载失败:", resp.Status)
		return
	}
	installShell, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Println(err.Error())
	}
	ExecCommand(string(installShell))
}

// ExecCommand streams output and preserves process errors without concurrent pipe races.
func ExecCommand(command string) error {
	cmd := exec.Command("bash", "-c", command)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	return cmd.Run()
}

// ExecCommandWithResult 运行命令并获取结果
func ExecCommandWithResult(command string) string {
	out, err := exec.Command("bash", "-c", command).CombinedOutput()
	if err != nil && !strings.Contains(err.Error(), "exit status") {
		fmt.Println("err: " + err.Error())
		return ""
	}
	return string(out)
}
