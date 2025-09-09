from flask import Flask, render_template, request, jsonify
import mysql.connector
from datetime import datetime
import os

app = Flask(__name__)

# MySQL 연결 설정
def get_db_connection():
    return mysql.connector.connect(
        host='localhost',
        database='calculator_db',
        user=os.environ.get('MYSQL_USER', 'lantine'),
        password=os.environ.get('MYSQL_PASSWORD', 'password')
    )

# 계산 결과를 데이터베이스에 저장
def save_calculation(expression, result):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        query = "INSERT INTO calculations (expression, result, created_at) VALUES (%s, %s, %s)"
        cursor.execute(query, (expression, result, datetime.now()))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Database error: {e}")
        return False

# 계산 기록 조회
def get_calculation_history():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        query = "SELECT expression, result, created_at FROM calculations ORDER BY created_at DESC LIMIT 50"
        cursor.execute(query)
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Database error: {e}")
        return []

@app.route('/')
def index():
    return render_template('calculator.html')

@app.route('/history')
def history():
    calculations = get_calculation_history()
    return render_template('history.html', calculations=calculations)

@app.route('/calculate', methods=['POST'])
def calculate():
    try:
        data = request.json
        expression = data.get('expression')
        
        # 안전한 계산을 위해 eval 대신 제한된 연산만 허용
        allowed_chars = set('0123456789+-*/.() ')
        if not all(c in allowed_chars for c in expression):
            return jsonify({'error': '허용되지 않는 문자가 포함되어 있습니다.'}), 400
        
        result = eval(expression)
        
        # 결과를 데이터베이스에 저장
        save_calculation(expression, result)
        
        return jsonify({'result': result})
    except Exception as e:
        return jsonify({'error': '계산 오류가 발생했습니다.'}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)