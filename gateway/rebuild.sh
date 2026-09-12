#!/bin/bash
set -e

echo "🚀 开始重建 Dify..."

# 清理
docker compose down -v

# 重建
#docker compose up -d --build --pull always --force-recreate
docker-compose up -d

# 等待
echo "⏳ 等待服务启动..."
sleep 30

# 迁移
docker exec -it dify-api flask db upgrade head

# 创建管理员
docker exec -it dify-api python3 -c "
from models.account import Account, AccountStatus
from extensions.ext_database import db
from werkzeug.security import generate_password_hash

if db.session.query(Account).count() == 0:
    admin = Account(
        email='vma@china.com',
        name='管理员',
        password=generate_password_hash('Admin123456!'),
        status=AccountStatus.ACTIVE.value
    )
    db.session.add(admin)
    db.session.commit()
    print('✅ 管理员账号创建成功')
else:
    print(f'⚠️  已有 {db.session.query(Account).count()} 个账号')
"

echo -e "\n✅ 部署完成！"
echo "🌐 访问: http://localhost:8083"
echo "📧 邮箱: vma@china.com"
echo "🔑 密码: Admin123456!"
