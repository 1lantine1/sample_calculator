-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS calculator_db;
USE calculator_db;

-- 계산 기록 테이블 생성
CREATE TABLE IF NOT EXISTS calculations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    expression VARCHAR(255) NOT NULL,
    result DECIMAL(20,10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성 (성능 향상을 위해)
CREATE INDEX idx_created_at ON calculations(created_at);