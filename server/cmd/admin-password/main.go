// admin-password（管理员口令工具）从终端或管道读取口令，只输出 bcrypt 哈希。
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"golang.org/x/crypto/bcrypt"
	"golang.org/x/term"
)

func main() {
	var password []byte
	var err error
	// 终端输入不回显；管道适用于秘密管理工具，避免命令行参数暴露口令。
	if term.IsTerminal(int(os.Stdin.Fd())) {
		fmt.Fprint(os.Stderr, "请输入只读管理员口令（至少12字节）：")
		password, err = term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
	} else {
		line, readErr := bufio.NewReader(os.Stdin).ReadString('\n')
		password = []byte(strings.TrimRight(line, "\r\n"))
		if readErr != nil && len(password) == 0 {
			err = readErr
		}
	}
	if err != nil || len(password) < 12 || len(password) > 72 {
		fmt.Fprintln(os.Stderr, "口令读取失败或长度不在12至72字节之间")
		os.Exit(1)
	}
	hash, err := bcrypt.GenerateFromPassword(password, 12)
	if err != nil {
		fmt.Fprintln(os.Stderr, "无法生成口令哈希")
		os.Exit(1)
	}
	fmt.Println(string(hash))
}
