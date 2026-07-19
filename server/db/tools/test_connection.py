#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
【重要】先在本机做端口映射
ssh -N -L 13306:127.0.0.1:3306 root@45.79.40.29

数据库连通性测试脚本
功能：验证能否连接到 MySQL/MariaDB，并确认能真实读到数据。
使用方法：python test_connection.py

配置与 export_schema.py 保持一致，支持用环境变量覆盖：
  MYSQL_HOST / MYSQL_PORT / MYSQL_USER / MYSQL_PASS / MYSQL_DB
"""

import os
import sys
import pymysql

# 数据库配置（从环境变量或使用默认值），与 export_schema.py 一致
DB_HOST = os.getenv('MYSQL_HOST', '127.0.0.1')
DB_PORT = int(os.getenv('MYSQL_PORT', '13306'))
DB_USER = os.getenv('MYSQL_USER', 'readingcoach')
DB_PASS = os.getenv('MYSQL_PASS', '')
DB_NAME = os.getenv('MYSQL_DB', 'ReadingCoach')


def _scalar(cursor):
    """取单值结果，None 结果安全兜底"""
    row = cursor.fetchone()
    return row[0] if row else None


def main():
    print("=" * 50)
    print("数据库连通性测试\n【重要提示】测试前先在本机做端口映射\nssh -N -L 13306:127.0.0.1:3306 root@45.79.40.29")
    print(f"目标: {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME}")
    print("=" * 50)

    connection = None
    try:
        # 1) 建立连接
        print("\n[1/4] 正在连接数据库 ...")
        connection = pymysql.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            database=DB_NAME,
            charset='utf8mb4',
            connect_timeout=8,
        )
        cursor = connection.cursor()
        print("      ✅ 连接成功")

        # 2) 读取服务器版本，确认握手正常
        print("\n[2/4] 读取服务器版本 ...")
        _ = cursor.execute("SELECT VERSION()")
        version = _scalar(cursor)
        print(f"      ✅ 服务器版本: {version}")

        # 3) 列出当前库的所有表
        print("\n[3/4] 列出数据表 ...")
        _ = cursor.execute("""
            SELECT TABLE_NAME
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = %s AND TABLE_TYPE = 'BASE TABLE'
            ORDER BY TABLE_NAME
        """, (DB_NAME,))
        tables = [str(row[0]) for row in cursor.fetchall()]

        if not tables:
            print("      ⚠️  连接成功，但该库没有任何表（可能还没导入 db/schema.sql）")
            return 1
        print(f"      ✅ 共发现 {len(tables)} 个表: {', '.join(tables)}")

        # 4) 逐表统计行数，确认能真正读到数据
        print("\n[4/4] 统计每个表的数据行数 ...")
        total_rows = 0
        for t in tables:
            _ = cursor.execute(f"SELECT COUNT(*) FROM `{t}`")
            count = int(_scalar(cursor) or 0)
            total_rows += count
            print(f"      - {t:<24} {count:>10,} 行")
        print(f"\n      ✅ 全部表可读，累计 {total_rows:,} 行数据")

        print("\n" + "=" * 50)
        print("🎉 测试通过：本机能连上数据库并读到数据")
        print("=" * 50)
        return 0

    except pymysql.err.OperationalError as e:
        code = e.args[0] if e.args else '?'
        print(f"\n❌ 连接/操作失败 (错误码 {code}): {e}")
        _hint(code)
        return 1
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        return 1
    finally:
        if connection:
            connection.close()


def _hint(code: int):
    """根据常见错误码给排查提示"""
    hints = {
        2003: "端口不通：检查服务器 bind-address、防火墙/安全组是否放行该端口。",
        1045: "账号或密码错误，或该账号 host 不允许从本机连接（需 GRANT ... @'%'）。",
        1049: "数据库不存在：确认库名，或先创建并导入 db/schema.sql。",
        1130: "该主机没有连接权限：检查账号 host 授权范围。",
    }
    tip = hints.get(code)
    if tip:
        print(f"   💡 提示: {tip}")


if __name__ == "__main__":
    sys.exit(main())
