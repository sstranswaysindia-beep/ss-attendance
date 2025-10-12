<?php
declare(strict_types=1);

// Test the fixed add_advance_transaction.php API
echo "<h2>Testing Fixed Add Advance Transaction API</h2>";

// Test data
$testData = [
    'driverId' => 169,
    'type' => 'expense',
    'amount' => 50.00,
    'description' => 'Test transaction after fixing apiSanitizeFloat',
];

echo "<h3>Test Data:</h3>";
echo "<pre>" . json_encode($testData, JSON_PRETTY_PRINT) . "</pre>";

// Make the API call
$url = 'https://sstranswaysindia.com/api/mobile/add_advance_transaction.php';
$options = [
    'http' => [
        'header' => "Content-Type: application/json\r\n",
        'method' => 'POST',
        'content' => json_encode($testData),
    ],
];

$context = stream_context_create($options);
$result = file_get_contents($url, false, $context);

echo "<h3>API Response:</h3>";
echo "<pre>" . htmlspecialchars($result) . "</pre>";

// Also test the common.php functions directly
echo "<h3>Testing Common Functions:</h3>";

// Include common.php to test functions
require_once __DIR__ . '/common.php';

echo "<p>Testing apiSanitizeFloat():</p>";
echo "<ul>";
echo "<li>apiSanitizeFloat('100.50') = " . (apiSanitizeFloat('100.50') ?? 'NULL') . "</li>";
echo "<li>apiSanitizeFloat('50') = " . (apiSanitizeFloat('50') ?? 'NULL') . "</li>";
echo "<li>apiSanitizeFloat('invalid') = " . (apiSanitizeFloat('invalid') ?? 'NULL') . "</li>";
echo "<li>apiSanitizeFloat(null) = " . (apiSanitizeFloat(null) ?? 'NULL') . "</li>";
echo "</ul>";

echo "<p>Testing apiSanitizeInt():</p>";
echo "<ul>";
echo "<li>apiSanitizeInt('169') = " . (apiSanitizeInt('169') ?? 'NULL') . "</li>";
echo "<li>apiSanitizeInt('invalid') = " . (apiSanitizeInt('invalid') ?? 'NULL') . "</li>";
echo "</ul>";

echo "<h3>✅ Test Complete!</h3>";
?>
