package trojan

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
	"trojan/core"
	"trojan/util"
)

var (
	dbDockerRun = "docker run --name trojan-mariadb --restart=always -p 127.0.0.1:%d:3306 -v /home/mariadb:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=%s -e MYSQL_ROOT_HOST=%% -e MYSQL_DATABASE=trojan -d mariadb:11.4"
)

// InstallMenu 安装目录
func InstallMenu() {
	fmt.Println()
	menu := []string{"更新trojan", "证书申请", "安装mysql"}
	switch util.LoopInput("请选择: ", menu, true) {
	case 1:
		InstallTrojan("")
	case 2:
		InstallTls()
	case 3:
		InstallMysql()
	default:
		return
	}
}

// InstallDocker installs Docker from Debian's maintained package repository.
func InstallDocker() {
	if util.CheckCommandExists("docker") {
		return
	}
	if err := util.ExecCommand("apt-get -o Acquire::ForceIPv4=true update && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y docker.io docker-cli && systemctl enable --now docker"); err != nil {
		fmt.Println("Docker 安装失败:", err)
	}
}

// InstallTrojan updates from this repository's independently built release.
func InstallTrojan(version string) error {
	args := []string{"/usr/local/lib/trojan-manager/scripts/update.sh"}
	if version != "" {
		args = append(args, "--version", version)
	}
	cmd := exec.Command("bash", args...)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	return cmd.Run()
}

// InstallTls validates issuance before changing certificate configuration.
func InstallTls() {
	config := core.GetConfig()
	if config == nil {
		fmt.Println("请先完成一键安装。")
		return
	}
	domain := util.Input("请输入证书域名（回车保留当前域名）: ", config.SSl.Sni)
	email := util.Input("联系邮箱（可留空）: ", "")
	args := []string{"/usr/local/lib/trojan-manager/scripts/certificates.sh", "--domain", domain}
	if email != "" {
		args = append(args, "--email", email)
	}
	cmd := exec.Command("bash", args...)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	if err := cmd.Run(); err != nil {
		fmt.Println("证书安装失败，已有配置保留:", err)
		return
	}
	Restart()
}

// InstallMysql 安装mysql
func InstallMysql() {
	var (
		mysql  core.Mysql
		choice int
	)
	fmt.Println()
	if util.IsExists("/.dockerenv") {
		choice = 2
	} else {
		choice = util.LoopInput("请选择: ", []string{"安装docker版mysql(mariadb)", "输入自定义mysql连接"}, true)
	}
	if choice < 0 {
		return
	} else if choice == 1 {
		mysql = core.Mysql{ServerAddr: "127.0.0.1", ServerPort: util.RandomPort(), Password: util.RandString(8, util.LETTER+util.DIGITS), Username: "root", Database: "trojan"}
		InstallDocker()
		// Never print database credentials.
		if util.CheckCommandExists("setenforce") {
			util.ExecCommand("setenforce 0")
		}
		if err := util.ExecCommand(fmt.Sprintf(dbDockerRun, mysql.ServerPort, mysql.Password)); err != nil {
			fmt.Println("数据库容器启动失败:", err)
			return
		}
		db := mysql.GetDB()
		deadline := time.Now().Add(90 * time.Second)
		for {
			if time.Now().After(deadline) {
				fmt.Println("数据库启动超时，请查看 Docker 日志。")
				return
			}
			fmt.Printf("%s mariadb启动中,请稍等...\n", time.Now().Format("2006-01-02 15:04:05"))
			err := db.Ping()
			if err == nil {
				db.Close()
				break
			} else {
				time.Sleep(2 * time.Second)
			}
		}
		fmt.Println("mariadb启动成功!")
	} else if choice == 2 {
		mysql = core.Mysql{}
		for {
			for {
				mysqlUrl := util.Input("请输入mysql连接地址(格式: host:port), 默认连接地址为127.0.0.1:3306, 使用直接回车, 否则输入自定义连接地址: ",
					"127.0.0.1:3306")
				urlInfo := strings.Split(mysqlUrl, ":")
				if len(urlInfo) != 2 {
					fmt.Printf("输入的%s不符合匹配格式(host:port)\n", mysqlUrl)
					continue
				}
				port, err := strconv.Atoi(urlInfo[1])
				if err != nil {
					fmt.Printf("%s不是数字\n", urlInfo[1])
					continue
				}
				mysql.ServerAddr, mysql.ServerPort = urlInfo[0], port
				break
			}
			mysql.Username = util.Input("请输入mysql的用户名(回车使用root): ", "root")
			mysql.Password = util.Input(fmt.Sprintf("请输入mysql %s用户的密码: ", mysql.Username), "")
			db := mysql.GetDB()
			if db != nil && db.Ping() == nil {
				mysql.Database = util.Input("请输入使用的数据库名(不存在可自动创建, 回车使用trojan): ", "trojan")
				db.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s;", mysql.Database))
				break
			} else {
				fmt.Println("连接mysql失败, 请重新输入")
			}
		}
	}
	mysql.CreateTable()
	core.WriteMysql(&mysql)
	if userList, _ := mysql.GetData(); len(userList) == 0 {
		AddUser()
	}
	Restart()
	fmt.Println()
}
