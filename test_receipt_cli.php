<?php
// Simple CLI test for receipt upload
echo "🧾 Receipt Upload Test\n";
echo "=====================\n\n";

// Test API endpoint
$url = 'https://sstranswaysindia.com/api/mobile/test_receipt_upload.php';

// Test 1: Check API connection
echo "1. Testing API connection...\n";
$response = file_get_contents($url);
$data = json_decode($response, true);

if ($data && $data['status'] === 'ok') {
    echo "✅ API is working!\n";
    echo "Supported formats: " . implode(', ', $data['supported_formats']) . "\n";
    echo "Max file size: " . $data['max_file_size'] . "\n\n";
} else {
    echo "❌ API connection failed!\n";
    echo "Response: " . $response . "\n\n";
    exit(1);
}

// Test 2: Test file upload (if a test file exists)
$testFile = __DIR__ . '/test_image.jpg';
if (file_exists($testFile)) {
    echo "2. Testing file upload...\n";
    
    $postData = [
        'transactionId' => 'test_123',
        'driverId' => '169',
        'receipt' => new CURLFile($testFile, 'image/jpeg', 'test_receipt.jpg')
    ];
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($data && $data['status'] === 'ok') {
        echo "✅ File upload successful!\n";
        echo "File saved to: " . $data['data']['filePath'] . "\n";
        echo "URL: " . $data['data']['url'] . "\n";
    } else {
        echo "❌ File upload failed!\n";
        echo "Response: " . $response . "\n";
    }
} else {
    echo "2. No test file found. Create a test_image.jpg file to test upload.\n";
}

echo "\n✅ Test completed!\n";
?>
