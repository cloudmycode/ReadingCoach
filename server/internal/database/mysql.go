// Package database 数据库连接管理
// 功能：
//   - 建立MySQL数据库连接
//   - 连接测试和错误处理
//   - 提供统一的数据库访问接口
//   - 支持腾讯云CDB连接配置
package database

import (
	"database/sql"
	"os"

	_ "github.com/go-sql-driver/mysql"

	"words/server/pkg/config"
)

func MustOpen(cfg config.Config) *sql.DB {
	db, err := sql.Open("mysql", cfg.DSN())
	if err != nil {
		// 数据库连接失败，直接退出程序
		os.Exit(1)
	}

	if err := db.Ping(); err != nil {
		// 数据库无法连接，直接退出程序
		os.Exit(1)
	}

	// 数据库连接成功，这个日志会在main.go中记录
	return db
}
