// fiti Remote Control Client
// Captures pointer events and sends them to the fiti WebSocket server

(function() {
    'use strict';

    const WS_URL = new URL('ws://' + location.host + '/remote-control');
    const CONNECT_TIMEOUT = 10000;

    let ws = null;
    let isConnected = false;
    let isPaired = false;
    let activeStrokeId = null;
    let currentTool = 'pen';
    let currentColor = '#FF0000';
    let currentWidth = 2.0;
    let accumulatedPoints = [];

    // UI elements
    const statusEl = document.getElementById('status');
    const pinDisplayEl = document.getElementById('pin-display');
    const pairingEl = document.getElementById('pairing');
    const pinInputEl = document.getElementById('pin-input');
    const pairBtnEl = document.getElementById('pair-btn');
    const pairErrorEl = document.getElementById('pair-error');
    const toolEl = document.getElementById('tool');
    const strokeInfoEl = document.getElementById('stroke-info');
    const canvas = document.getElementById('drawingCanvas');
    const ctx = canvas.getContext('2d');

    // Canvas setup for visual feedback
    function resizeCanvas() {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.strokeStyle = currentColor;
        ctx.lineWidth = currentWidth * canvas.width; // Scale width
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
    }
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    // WebSocket connection
    function connect() {
        ws = new WebSocket(WS_URL);

        ws.onopen = function() {
            console.log('WebSocket connected');
            statusEl.textContent = 'Connected - Waiting for pairing...';
            // Pairing overlay is still visible, user needs to enter PIN
        };

        ws.onmessage = function(event) {
            try {
                const msg = JSON.parse(event.data);
                handleMessage(msg);
            } catch (e) {
                console.error('Failed to parse message:', e);
            }
        };

        ws.onclose = function() {
            console.log('WebSocket closed');
            isConnected = false;
            isPaired = false;
            activeStrokeId = null;
            statusEl.textContent = 'Disconnected';
            statusEl.className = '';
            pairingEl.classList.remove('hidden');
            
            // Clear canvas on disconnect
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            
            // Retry connection after delay
            setTimeout(connect, 3000);
        };

        ws.onerror = function(error) {
            console.error('WebSocket error:', error);
        };
    }

    // Handle incoming messages
    function handleMessage(msg) {
        console.log('Received:', msg.type, msg);
        switch (msg.type) {
            case 'pairChallenge':
                // Show the PIN (server sends it, though we could just display our own)
                pinDisplayEl.textContent = msg.pin || '----';
                pinInputEl.focus();
                break;
            case 'pairResult':
                if (msg.ok) {
                    isPaired = true;
                    isConnected = true;
                    statusEl.textContent = 'Connected - ' + (msg.controllerName || 'Controller');
                    statusEl.className = 'connected';
                    pairingEl.classList.add('hidden');
                    if (msg.token) {
                        localStorage.setItem('fiti_remote_token', msg.token);
                    }
                } else {
                    pairErrorEl.textContent = msg.message || 'Invalid PIN';
                    pairErrorEl.style.display = 'block';
                }
                break;
            case 'ack':
                // Operation successful
                break;
            case 'error':
                console.error('Server error:', msg.message);
                break;
            case 'sessionState':
                // Server confirmed session state
                break;
        }
    }

    // Send pairing request
    function sendPair() {
        const pin = pinInputEl.value.trim();
        const remember = document.getElementById('remember').checked;
        const clientName = 'iPad ' + (navigator.platform || 'Device');

        const message = {
            type: 'pairing',
            clientId: clientName,
            pin: pin,
            remember: remember
        };

        ws.send(JSON.stringify(message));
    }

    // Send stroke messages
    function sendStartStroke(point) {
        activeStrokeId = generateId();
        accumulatedPoints = [];

        const message = {
            type: 'startStroke',
            strokeId: activeStrokeId,
            tool: currentTool,
            color: currentColor,
            width: currentWidth,
            point: point
        };

        ws.send(JSON.stringify(message));
        strokeInfoEl.textContent = 'Drawing stroke ' + activeStrokeId.substring(0, 8);
        drawPoint(point);
    }

    function sendAppendPoints(points) {
        if (!activeStrokeId) return;

        const message = {
            type: 'appendPoints',
            strokeId: activeStrokeId,
            points: points
        };

        ws.send(JSON.stringify(message));
        
        // Draw locally for feedback
        points.forEach(p => drawPoint(p));
    }

    function sendEndStroke() {
        if (!activeStrokeId) return;

        const message = {
            type: 'endStroke',
            strokeId: activeStrokeId
        };

        ws.send(JSON.stringify(message));
        activeStrokeId = null;
        accumulatedPoints = [];
        strokeInfoEl.textContent = 'No active stroke';
    }

    // Draw locally for visual feedback
    function drawPoint(point) {
        const x = point.x * canvas.width;
        const y = point.y * canvas.height;

        ctx.beginPath();
        ctx.arc(x, y, 5, 0, Math.PI * 2);
        ctx.fillStyle = currentColor;
        ctx.fill();
    }

    // Generate unique stroke ID
    function generateId() {
        return Math.random().toString(36).substring(2, 15);
    }

    // Normalize coordinates to 0-1 range
    function normalizePoint(x, y) {
        return {
            x: x / canvas.width,
            y: y / canvas.height
        };
    }

    // Pointer event handlers
    let isDrawing = false;

    canvas.addEventListener('pointerdown', function(e) {
        e.preventDefault();
        isDrawing = true;
        canvas.setPointerCapture(e.pointerId);

        const point = normalizePoint(e.clientX, e.clientY);
        point.pressure = e.pressure || 1.0;
        point.t = Date.now();

        sendStartStroke(point);
    });

    canvas.addEventListener('pointermove', function(e) {
        if (!isDrawing) return;
        e.preventDefault();

        const point = normalizePoint(e.clientX, e.clientY);
        point.pressure = e.pressure || 1.0;
        point.t = Date.now();

        accumulatedPoints.push(point);

        // Send batches every 10 points or 100ms
        if (accumulatedPoints.length >= 10) {
            sendAppendPoints([...accumulatedPoints]);
            accumulatedPoints = [];
        }
    });

    canvas.addEventListener('pointerup', function(e) {
        e.preventDefault();
        if (!isDrawing) return;

        isDrawing = false;
        canvas.releasePointerCapture(e.pointerId);

        // Send any remaining points
        if (accumulatedPoints.length > 0) {
            sendAppendPoints([...accumulatedPoints]);
            accumulatedPoints = [];
        }

        sendEndStroke();
    });

    canvas.addEventListener('pointercancel', function(e) {
        e.preventDefault();
        if (!isDrawing) return;

        isDrawing = false;
        canvas.releasePointerCapture(e.pointerId);

        if (accumulatedPoints.length > 0) {
            sendAppendPoints([...accumulatedPoints]);
            accumulatedPoints = [];
        }

        sendEndStroke();
    });

    // Handle pairing button and input
    pairBtnEl.addEventListener('click', sendPair);
    pinInputEl.addEventListener('keypress', function(e) {
        if (e.key === 'Enter') {
            sendPair();
        }
    });

    // Connect on page load
    connect();

})();
