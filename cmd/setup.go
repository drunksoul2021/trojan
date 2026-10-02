package cmd

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"regexp"
	"time"
	"trojan/core"
)

func setupManager() error {
	config := core.GetConfig()
	if config == nil {
		return fmt.Errorf("无法读取 Trojan 配置")
	}
	admin, _ := core.GetValue("admin_pass")
	password := os.Getenv("TROJAN_ADMIN_PASSWORD")
	username := os.Getenv("TROJAN_ADMIN_USER")
	if username == "" {
		username = "admin"
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_.-]{1,64}$`).MatchString(username) {
		return fmt.Errorf("管理员用户名只允许 1 至 64 位字母、数字、下划线、点和横线")
	}
	if admin == "" && len(password) < 6 {
		return fmt.Errorf("首次初始化请设置至少 6 位 TROJAN_ADMIN_PASSWORD")
	}
	db := config.Mysql.GetDB()
	if db == nil {
		return fmt.Errorf("数据库连接配置不正确")
	}
	defer db.Close()
	var err error
	for attempt := 0; attempt < 30; attempt++ {
		if err = db.Ping(); err == nil {
			break
		}
		time.Sleep(time.Second)
	}
	if err != nil {
		return fmt.Errorf("数据库启动超时，请检查 Docker 容器日志: %w", err)
	}
	if _, err = db.Exec(core.CreateTableSql); err != nil {
		return err
	}
	if admin == "" {
		if err = core.SetValue("admin_user", username); err != nil {
			return err
		}
		hash := sha256.Sum224([]byte(password))
		if err = core.SetValue("admin_pass", hex.EncodeToString(hash[:])); err != nil {
			return err
		}
	}
	var count int
	if err = db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		random := make([]byte, 24)
		if _, err = rand.Read(random); err != nil {
			return err
		}
		pass := hex.EncodeToString(random)
		if err = config.Mysql.CreateUser("owner", base64.StdEncoding.EncodeToString([]byte(pass)), pass); err != nil {
			return err
		}
		access := fmt.Sprintf("管理后台: https://%s:%d\n管理员: %s\n客户端用户名: owner\n客户端密码: %s\n", config.SSl.Sni, config.LocalPort, core.AdminUsername(), pass)
		path := os.Getenv("TROJAN_ACCESS_FILE")
		if path == "" {
			path = "/root/trojan-access.txt"
		}
		if err = os.WriteFile(path, []byte(access), 0600); err != nil {
			return err
		}
		if err = os.Chmod(path, 0600); err != nil {
			return err
		}
	}
	fmt.Println("数据库及管理账号初始化完成，已有用户和管理员密码保留。")
	return nil
}
func init() {
	rootCmd.AddCommand(&cobra.Command{Use: "setup", Short: "初始化数据库及管理账号（保留已有数据）", RunE: func(cmd *cobra.Command, args []string) error { return setupManager() }})
}
