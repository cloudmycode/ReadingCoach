#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
数据库完整导出脚本
功能：连接MySQL数据库，导出所有表的结构和数据到SQL文件
使用方法：python export_schema.py [选项] [输出文件名]
选项：
  --schema-only    仅导出表结构
  --data-only      仅导出数据
  --full           导出完整数据库（结构+数据，默认）
  --help           显示帮助信息
"""

import os
import sys
import pymysql
import argparse
from datetime import datetime

# 数据库配置（从环境变量或使用默认值）
DB_CONFIG = {
    'host': os.getenv('MYSQL_HOST', '127.0.0.1'),
    'port': int(os.getenv('MYSQL_PORT', '13306')),
    'user': os.getenv('MYSQL_USER', 'readingcoach'),
    'password': os.getenv('MYSQL_PASS', ''),
    'database': os.getenv('MYSQL_DB', 'ReadingCoach'),
    'charset': 'utf8mb4'
}

def get_table_info(cursor, database):
    """获取数据库表信息"""
    cursor.execute("""
        SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH
        FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA = %s 
        AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME
    """, (database,))
    
    tables = []
    for row in cursor.fetchall():
        tables.append({
            'name': row[0],
            'rows': row[1] or 0,
            'data_length': row[2] or 0,
            'index_length': row[3] or 0
        })
    
    return tables

def export_table_schema(cursor, f, table_name):
    """导出单个表的结构"""
    cursor.execute(f"SHOW CREATE TABLE `{table_name}`")
    create_sql = cursor.fetchone()[1]
    
    f.write(f"-- ----------------------------\n")
    f.write(f"-- 表结构: {table_name}\n")
    f.write(f"-- ----------------------------\n")
    f.write(f"DROP TABLE IF EXISTS `{table_name}`;\n")
    f.write(f"{create_sql};\n\n")

def export_table_data(cursor, f, table_name, batch_size=1000):
    """导出单个表的数据"""
    # 获取表的总行数
    cursor.execute(f"SELECT COUNT(*) FROM `{table_name}`")
    total_rows = cursor.fetchone()[0]
    
    if total_rows == 0:
        f.write(f"-- 表 {table_name} 无数据\n\n")
        return 0
    
    f.write(f"-- ----------------------------\n")
    f.write(f"-- 表数据: {table_name} (共 {total_rows} 行)\n")
    f.write(f"-- ----------------------------\n")
    
    # 获取列信息
    cursor.execute(f"DESCRIBE `{table_name}`")
    columns = [row[0] for row in cursor.fetchall()]
    
    # 分批导出数据
    exported_rows = 0
    offset = 0
    
    while offset < total_rows:
        cursor.execute(f"SELECT * FROM `{table_name}` LIMIT {batch_size} OFFSET {offset}")
        rows = cursor.fetchall()
        
        if not rows:
            break
        
        # 构建INSERT语句
        columns_str = ', '.join([f"`{col}`" for col in columns])
        f.write(f"INSERT INTO `{table_name}` ({columns_str}) VALUES\n")
        
        values_list = []
        for row in rows:
            # 处理NULL值和字符串转义
            processed_row = []
            for value in row:
                if value is None:
                    processed_row.append('NULL')
                elif isinstance(value, str):
                    # 转义单引号
                    escaped_value = value.replace("'", "''")
                    processed_row.append(f"'{escaped_value}'")
                elif isinstance(value, (int, float)):
                    processed_row.append(str(value))
                else:
                    processed_row.append(f"'{str(value)}'")
            
            values_list.append(f"({', '.join(processed_row)})")
        
        f.write(',\n'.join(values_list))
        f.write(";\n\n")
        
        exported_rows += len(rows)
        offset += batch_size
        
        # 显示进度
        progress = (exported_rows / total_rows) * 100
        print(f"  📊 进度: {exported_rows}/{total_rows} ({progress:.1f}%)")
    
    return exported_rows

def export_database(output_file=None, export_type='full'):
    """导出数据库（结构、数据或完整）"""
    
    # 设置输出文件名
    if not output_file:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        suffix = {
            'schema': 'schema',
            'data': 'data', 
            'full': 'complete'
        }[export_type]
        output_file = f"database_{suffix}_{timestamp}.sql"
    
    # 确保输出文件在sql目录中
    if not os.path.isabs(output_file):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        output_file = os.path.join(script_dir, output_file)
    
    print(f"🚀 开始导出数据库...")
    print(f"📊 数据库: {DB_CONFIG['database']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print(f"📁 输出文件: {output_file}")
    print(f"🔧 导出类型: {export_type}")
    
    try:
        # 连接数据库
        connection = pymysql.connect(**DB_CONFIG)
        cursor = connection.cursor()
        
        # 获取表信息
        tables = get_table_info(cursor, DB_CONFIG['database'])
        
        if not tables:
            print("⚠️  数据库中没有找到任何表")
            return False
        
        # 显示表统计信息
        total_rows = sum(table['rows'] for table in tables)
        total_size = sum(table['data_length'] + table['index_length'] for table in tables)
        print(f"📋 发现 {len(tables)} 个表，共 {total_rows:,} 行数据，大小约 {total_size / 1024 / 1024:.1f} MB")
        
        # 开始写入SQL文件
        with open(output_file, 'w', encoding='utf-8') as f:
            # 写入文件头
            export_desc = {
                'schema': '表结构',
                'data': '数据',
                'full': '完整数据库（结构+数据）'
            }[export_type]
            
            f.write(f"""-- 数据库{export_desc}导出
-- 数据库: {DB_CONFIG['database']}
-- 导出时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
-- 导出类型: {export_desc}
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_unicode_ci

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

""")
            
            exported_tables = 0
            exported_rows = 0
            
            # 导出每个表
            for i, table in enumerate(tables):
                table_name = table['name']
                print(f"📋 正在处理表 {i+1}/{len(tables)}: {table_name} ({table['rows']:,} 行)")
                
                # 导出表结构
                if export_type in ['schema', 'full']:
                    export_table_schema(cursor, f, table_name)
                
                # 导出表数据
                if export_type in ['data', 'full']:
                    rows_exported = export_table_data(cursor, f, table_name)
                    exported_rows += rows_exported
                
                exported_tables += 1
            
            f.write("SET FOREIGN_KEY_CHECKS = 1;\n")
        
        # 统计信息
        file_size = os.path.getsize(output_file)
        print(f"\n✅ 导出成功！")
        print(f"📄 文件位置: {output_file}")
        print(f"📏 文件大小: {file_size / 1024 / 1024:.1f} MB")
        print(f"📋 处理表数量: {exported_tables}")
        if export_type in ['data', 'full']:
            print(f"📊 导出数据行数: {exported_rows:,}")
        
        return True
        
    except Exception as e:
        print(f"❌ 导出失败: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        if 'connection' in locals():
            connection.close()
    
    print("🎉 导出完成！")
    return True

def parse_arguments():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description='MySQL数据库导出工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python export_schema.py                    # 完整导出（默认）
  python export_schema.py --schema-only     # 仅导出表结构
  python export_schema.py --data-only       # 仅导出数据
  python export_schema.py --full backup.sql # 完整导出到指定文件
  python export_schema.py --help             # 显示帮助信息
        """
    )
    
    # 导出类型选项（互斥）
    export_group = parser.add_mutually_exclusive_group()
    export_group.add_argument('--schema-only', action='store_true', 
                             help='仅导出表结构')
    export_group.add_argument('--data-only', action='store_true',
                             help='仅导出数据')
    export_group.add_argument('--full', action='store_true', default=True,
                             help='导出完整数据库（结构+数据，默认）')
    
    # 输出文件
    parser.add_argument('output_file', nargs='?', 
                       help='输出SQL文件名（可选）')
    
    return parser.parse_args()

if __name__ == "__main__":
    # 解析命令行参数
    args = parse_arguments()
    
    # 确定导出类型
    if args.schema_only:
        export_type = 'schema'
    elif args.data_only:
        export_type = 'data'
    else:
        export_type = 'full'
    
    # 执行导出
    success = export_database(args.output_file, export_type)
    
    if success:
        print("🎉 导出完成！")
        sys.exit(0)
    else:
        print("❌ 导出失败！")
        sys.exit(1)
