#!/bin/bash

# 웹서버 설치 및 설정 스크립트 (리포지토리 활성화 및 안정성 강화 버전)
# 이 스크립트는 Azure VM에서 자동으로 실행되어 Python 웹 계산기를 설치합니다.

set -e

# 파라미터 받기
MYSQL_USERNAME="$1"
MYSQL_PASSWORD="$2"
SCRIPTS_BASE_URI="$3"

# 로그 파일 설정
LOGFILE="/var/log/setup_webserver.log"
touch $LOGFILE

# 로그 함수 정의
log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $1" | tee -a $LOGFILE
}

log "=== 웹서버 설치 시작 ==="
log "시작 시간: $(date)"
log "MySQL 사용자: $MYSQL_USERNAME"
log "스크립트 URI: $SCRIPTS_BASE_URI"

# --- [수정 1: 안정적인 시스템 업데이트 및 리포지토리 활성화] ---
# 다른 apt 프로세스가 끝날 때까지 대기
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
   log "다른 apt/dpkg 프로세스가 끝날 때까지 대기 중..."
   sleep 10
done

# 리포지토리 관리 도구 설치
log "리포지토리 관리 도구(software-properties-common) 설치 중..."
apt-get update -y
apt-get install -y software-properties-common

# 'universe' 리포지토리 명시적 활성화
log "'universe' 리포지토리를 활성화합니다..."
add-apt-repository universe -y

# apt 캐시를 초기화하고 패키지 목록 다시 업데이트
log "apt 캐시를 초기화하고 패키지 목록을 다시 업데이트합니다..."
apt-get clean
apt-get update -y

# 시스템 업그레이드
log "시스템 업그레이드 중..."
apt-get upgrade -y
# --- [수정 완료] ---


# 필요한 패키지 설치
log "필요한 패키지 설치 중..."
apt-get install -y python3 python3-pip python3-venv mysql-server nginx git wget curl

# (이하 스크립트는 이전과 동일합니다)

# MySQL 서버 시작 및 설정
log "MySQL 서버 설정 중..."
systemctl start mysql
systemctl enable mysql

log "MySQL 서비스가 완전히 시작될 때까지 대기 중..."
for i in {1..10}; do
    if mysqladmin ping > /dev/null 2>&1; then
        log "MySQL 서버 준비 완료."
        break
    fi
    log "MySQL 서버 대기 중... ($i/10)"
    sleep 3
done
if ! mysqladmin ping > /dev/null 2>&1; then
    log "MySQL 서버 시작 실패."
    exit 1
fi

log "MySQL 보안 설정 적용 중..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD';"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p"$MYSQL_PASSWORD" -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -p"$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;"

log "애플리케이션 데이터베이스 및 사용자 생성 중..."
mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS calculator_db;"
mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER '$MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL PRIVILEGES ON calculator_db.* TO '$MYSQL_USERNAME'@'localhost';"
mysql -u root -p"$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;"

log "애플리케이션 디렉토리 생성 중..."
APP_DIR="/var/www/calculator"
mkdir -p $APP_DIR
cd $APP_DIR

log "애플리케이션 파일 다운로드 중..."
wget "$SCRIPTS_BASE_URI/app.py" -O app.py
wget "$SCRIPTS_BASE_URI/requirements.txt" -O requirements.txt
wget "$SCRIPTS_BASE_URI/database_init.sql" -O database_init.sql

mkdir -p templates static
wget "$SCRIPTS_BASE_URI/templates/calculator.html" -O templates/calculator.html
wget "$SCRIPTS_BASE_URI/templates/history.html" -O templates/history.html
wget "$SCRIPTS_BASE_URI/static/style.css" -O static/style.css
wget "$SCRIPTS_BASE_URI/static/calculator.js" -O static/calculator.js

log "Python 가상환경 설정 중..."
python3 -m venv venv
. venv/bin/activate

log "Python 패키지 설치 중..."
pip install --upgrade pip
pip install -r requirements.txt

log "데이터베이스 초기화 중..."
mysql -u root -p"$MYSQL_PASSWORD" < database_init.sql

log "시스템 서비스 설정 중..."
cat > /etc/systemd/system/calculator.service << EOF
[Unit]
Description=Calculator Web Application
After=network.target mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/calculator
Environment="MYSQL_USER=$MYSQL_USERNAME"
Environment="MYSQL_PASSWORD=$MYSQL_PASSWORD"
ExecStart=/var/www/calculator/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chown -R www-data:www-data $APP_DIR

log "서비스 데몬 리로드 및 계산기 서비스 시작..."
systemctl daemon-reload
systemctl start calculator
systemctl enable calculator

log "Nginx 설정 중..."
cat > /etc/nginx/sites-available/calculator << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/calculator /etc/nginx/sites-enabled/

log "Nginx 설정 테스트 및 재시작..."
nginx -t
systemctl restart nginx
systemctl enable nginx

if command -v ufw > /dev/null; then
    log "방화벽 설정 중..."
    ufw allow 22/tcp  # SSH
    ufw allow 80/tcp  # HTTP
    ufw --force enable
fi

log "=== 서비스 상태 확인 ==="
systemctl status calculator --no-pager | tee -a $LOGFILE
systemctl status nginx --no-pager | tee -a $LOGFILE
systemctl status mysql --no-pager | tee -a $LOGFILE

log "=== 웹서버 설치 완료 ==="
log "완료 시간: $(date)"
PUBLIC_IP=$(curl -s ifconfig.me)
log "웹사이트 URL: http://$PUBLIC_IP"
log "계산기: http://$PUBLIC_IP/"
log "기록 조회: http://$PUBLIC_IP/history"
log "로그 파일: $LOGFILE"
