#!/bin/bash

# 웹서버 설치 및 설정 스크립트 (안정성 개선 버전)
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
    # ISO 8601 형식의 타임스탬프 추가
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $1" | tee -a $LOGFILE
}

log "=== 웹서버 설치 시작 ==="
log "시작 시간: $(date)"
log "MySQL 사용자: $MYSQL_USERNAME"
log "스크립트 URI: $SCRIPTS_BASE_URI"

# --- [수정 1: 안정적인 시스템 업데이트] ---
# 다른 apt 프로세스가 끝날 때까지 대기 (unattended-upgrades 등)
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
   log "다른 apt/dpkg 프로세스가 끝날 때까지 대기 중..."
   sleep 10
done

# 네트워크 불안정에 대비하여 apt-get update 재시도 로직 추가
log "시스템 업데이트 중 (최대 3회 시도)..."
for i in 1 2 3; do
  apt-get update -y && break  # 성공하면 루프 탈출
  log "apt-get update 실패. 15초 후 재시도... (시도 $i/3)"
  sleep 15
done

# 시스템 업그레이드
log "시스템 업그레이드 중..."
apt-get upgrade -y

# 필요한 패키지 설치
log "필요한 패키지 설치 중..."
apt-get install -y python3 python3-pip python3-venv mysql-server nginx git wget curl

# MySQL 서버 시작 및 설정
log "MySQL 서버 설정 중..."
systemctl start mysql
systemctl enable mysql

# --- [수정 2: MySQL 서비스 안정화 대기] ---
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


# MySQL root 비밀번호 설정 및 보안 설정
log "MySQL 보안 설정 적용 중..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD';"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p"$MYSQL_PASSWORD" -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p"$MYSQL_PASSWORD" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -p"$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;"

# 애플리케이션 사용자 및 데이터베이스 생성
log "애플리케이션 데이터베이스 및 사용자 생성 중..."
mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS calculator_db;"
mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER '$MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL PRIVILEGES ON calculator_db.* TO '$MYSQL_USERNAME'@'localhost';"
mysql -u root -p"$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;"

# 애플리케이션 디렉토리 생성
log "애플리케이션 디렉토리 생성 중..."
APP_DIR="/var/www/calculator"
mkdir -p $APP_DIR
cd $APP_DIR

# GitHub에서 애플리케이션 파일 다운로드
log "애플리케이션 파일 다운로드 중..."
wget "$SCRIPTS_BASE_URI/app.py" -O app.py
wget "$SCRIPTS_BASE_URI/requirements.txt" -O requirements.txt
wget "$SCRIPTS_BASE_URI/database_init.sql" -O database_init.sql

# 템플릿 및 정적 파일 디렉토리 생성
mkdir -p templates static

# 템플릿 파일 다운로드
wget "$SCRIPTS_BASE_URI/templates/calculator.html" -O templates/calculator.html
wget "$SCRIPTS_BASE_URI/templates/history.html" -O templates/history.html

# 정적 파일 다운로드
wget "$SCRIPTS_BASE_URI/static/style.css" -O static/style.css
wget "$SCRIPTS_BASE_URI/static/calculator.js" -O static/calculator.js

# Python 가상환경 생성 및 활성화
log "Python 가상환경 설정 중..."
python3 -m venv venv
source venv/bin/activate

# Python 패키지 설치
log "Python 패키지 설치 중..."
pip install --upgrade pip
pip install -r requirements.txt

# 데이터베이스 초기화
log "데이터베이스 초기화 중..."
mysql -u root -p"$MYSQL_PASSWORD" < database_init.sql

# 환경변수 설정을 위한 서비스 파일 생성
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
# 환경변수는 실제 값으로 직접 주입합니다.
Environment="MYSQL_USER=$MYSQL_USERNAME"
Environment="MYSQL_PASSWORD=$MYSQL_PASSWORD"
ExecStart=/var/www/calculator/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 서비스 권한 설정
chown -R www-data:www-data $APP_DIR
# app.py는 실행 권한이 필요 없습니다. python 인터프리터가 실행합니다.

# 서비스 시작 및 활성화
log "서비스 데몬 리로드 및 계산기 서비스 시작..."
systemctl daemon-reload
systemctl start calculator
systemctl enable calculator

# Nginx 설정
log "Nginx 설정 중..."
cat > /etc/nginx/sites-available/calculator << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        # --- [수정 3: 프록시 포트 변경] ---
        # Nginx(80) -> Python App(5000)으로 요청 전달
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# 기본 nginx 사이트 비활성화 및 계산기 사이트 활성화
rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/calculator /etc/nginx/sites-enabled/

# Nginx 설정 테스트 및 재시작
log "Nginx 설정 테스트 및 재시작..."
nginx -t
systemctl restart nginx
systemctl enable nginx

# 방화벽 설정 (UFW가 설치된 경우)
if command -v ufw > /dev/null; then
    log "방화벽 설정 중..."
    ufw allow 22/tcp  # SSH
    ufw allow 80/tcp  # HTTP
    ufw --force enable
fi

# 서비스 상태 확인
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
