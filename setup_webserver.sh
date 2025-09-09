#!/bin/bash

# 웹서버 설치 및 설정 스크립트
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
    echo "$1" | tee -a $LOGFILE
}

log "=== 웹서버 설치 시작 ==="
log "시작 시간: $(date)"
log "MySQL 사용자: $MYSQL_USERNAME"
log "스크립트 URI: $SCRIPTS_BASE_URI"

# 시스템 업데이트
log "시스템 업데이트 중..."
apt-get update -y
apt-get upgrade -y

# 필요한 패키지 설치
log "필요한 패키지 설치 중..."
apt-get install -y python3 python3-pip python3-venv mysql-server nginx git wget curl

# MySQL 서버 시작 및 설정
log "MySQL 서버 설정 중..."
systemctl start mysql
systemctl enable mysql

# MySQL root 비밀번호 설정 및 보안 설정
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD';"
mysql -u root -p$MYSQL_PASSWORD -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p$MYSQL_PASSWORD -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p$MYSQL_PASSWORD -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p$MYSQL_PASSWORD -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -p$MYSQL_PASSWORD -e "FLUSH PRIVILEGES;"

# 애플리케이션 사용자 및 데이터베이스 생성
log "애플리케이션 데이터베이스 사용자 생성 중..."
mysql -u root -p$MYSQL_PASSWORD -e "CREATE USER '$MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -p$MYSQL_PASSWORD -e "GRANT ALL PRIVILEGES ON calculator_db.* TO '$MYSQL_USERNAME'@'localhost';"
mysql -u root -p$MYSQL_PASSWORD -e "FLUSH PRIVILEGES;"

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
mysql -u root -p$MYSQL_PASSWORD < database_init.sql

# 환경변수 설정을 위한 서비스 파일 생성
log "시스템 서비스 설정 중..."
cat > /etc/systemd/system/calculator.service << 'EOF'
[Unit]
Description=Calculator Web Application
After=network.target mysql.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/calculator
Environment=MYSQL_USER=MYSQL_USERNAME_PLACEHOLDER
Environment=MYSQL_PASSWORD=MYSQL_PASSWORD_PLACEHOLDER
ExecStart=/var/www/calculator/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 서비스 파일에서 플레이스홀더를 실제 값으로 교체
sed -i "s/MYSQL_USERNAME_PLACEHOLDER/$MYSQL_USERNAME/g" /etc/systemd/system/calculator.service
sed -i "s/MYSQL_PASSWORD_PLACEHOLDER/$MYSQL_PASSWORD/g" /etc/systemd/system/calculator.service

# 서비스 권한 설정
chown -R www-data:www-data $APP_DIR
chmod +x app.py

# 서비스 시작 및 활성화
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
        proxy_pass http://127.0.0.1:80;
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
nginx -t
systemctl restart nginx
systemctl enable nginx

# 방화벽 설정 (UFW가 설치된 경우)
if command -v ufw > /dev/null; then
    log "방화벽 설정 중..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 3306/tcp
    echo "y" | ufw enable
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