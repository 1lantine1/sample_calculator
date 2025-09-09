let currentInput = '';
let shouldResetDisplay = false;

function appendToDisplay(value) {
    const display = document.getElementById('result');
    const errorDiv = document.getElementById('error-message');
    errorDiv.textContent = '';
    
    if (shouldResetDisplay) {
        display.value = '';
        shouldResetDisplay = false;
    }
    
    if (display.value === '0' && value !== '.') {
        display.value = value;
    } else {
        display.value += value;
    }
    currentInput = display.value;
}

function clearDisplay() {
    const display = document.getElementById('result');
    const errorDiv = document.getElementById('error-message');
    display.value = '';
    currentInput = '';
    errorDiv.textContent = '';
}

function deleteLast() {
    const display = document.getElementById('result');
    display.value = display.value.slice(0, -1);
    currentInput = display.value;
    
    if (display.value === '') {
        display.value = '';
    }
}

async function calculate() {
    const display = document.getElementById('result');
    const errorDiv = document.getElementById('error-message');
    
    if (!currentInput) {
        return;
    }
    
    try {
        // 곱하기 기호 변환 (× → *)
        const expression = currentInput.replace(/×/g, '*');
        
        const response = await fetch('/calculate', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ expression: expression })
        });
        
        const data = await response.json();
        
        if (response.ok) {
            display.value = data.result;
            currentInput = data.result.toString();
            shouldResetDisplay = true;
            errorDiv.textContent = '';
        } else {
            errorDiv.textContent = data.error || '계산 오류가 발생했습니다.';
        }
    } catch (error) {
        errorDiv.textContent = '서버 연결 오류가 발생했습니다.';
        console.error('Error:', error);
    }
}

// 키보드 입력 지원
document.addEventListener('keydown', function(event) {
    const key = event.key;
    
    // 숫자 및 연산자 입력
    if ('0123456789'.includes(key)) {
        appendToDisplay(key);
    } else if ('+-*/'.includes(key)) {
        if (key === '*') {
            appendToDisplay('×');
        } else {
            appendToDisplay(key);
        }
    } else if (key === '.') {
        appendToDisplay('.');
    } else if (key === 'Enter' || key === '=') {
        event.preventDefault();
        calculate();
    } else if (key === 'Escape' || key === 'c' || key === 'C') {
        clearDisplay();
    } else if (key === 'Backspace') {
        deleteLast();
    }
});