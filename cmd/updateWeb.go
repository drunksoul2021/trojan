package cmd

import (
	"github.com/spf13/cobra"
	"trojan/util"
)

// updateWebCmd represents the update command
var updateWebCmd = &cobra.Command{
	Use:   "updateWeb",
	Short: "更新trojan管理程序",
	Run: func(cmd *cobra.Command, args []string) {
		util.ExecCommand("bash /usr/local/lib/trojan-manager/scripts/update.sh")
	},
}

func init() {
	rootCmd.AddCommand(updateWebCmd)
}
