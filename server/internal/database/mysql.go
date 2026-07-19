// Package database 数据库连接管理
// 功能：
//   - 建立MySQL数据库连接
//   - 连接测试和错误处理
//   - 提供统一的数据库访问接口
//   - 支持腾讯云CDB连接配置
package database

import (
	"database/sql"
	"log"

	_ "github.com/go-sql-driver/mysql"

	"words/server/pkg/config"
)

func MustOpen(cfg config.Config) *sql.DB {
	// 连接信息（不含密码），便于排查
	target := cfg.MySQLUser + "@" + cfg.MySQLHost + ":" + cfg.MySQLPort + "/" + cfg.MySQLDB

	db, err := sql.Open("mysql", cfg.DSN())
	if err != nil {
		log.Fatalf("❌ 初始化数据库连接失败 (%s): %v", target, err)
	}

	if err := db.Ping(); err != nil {
		log.Fatalf("❌ 数据库连接失败 (%s): %v", target, err)
	}

	// 数据库连接成功，这个日志会在main.go中记录
	return db
}
