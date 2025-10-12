<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Simple test endpoint
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        echo json_encode([
            'status' => 'error',
            'error' => 'Invalid JSON: ' . json_last_error_msg(),
            'received_input' => $input
        ]);
        exit;
    }
    
    // Test response
    echo json_encode([
        'status' => 'ok',
        'message' => 'API is working',
        'received_data' => $data,
        'timestamp' => date('Y-m-d H:i:s'),
        'method' => $_SERVER['REQUEST_METHOD']
    ]);
} else {
    // GET request
    echo json_encode([
        'status' => 'ok',
        'message' => 'API is accessible',
        'timestamp' => date('Y-m-d H:i:s'),
        'method' => $_SERVER['REQUEST_METHOD']
    ]);
}
?>
