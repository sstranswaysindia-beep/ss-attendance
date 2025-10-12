<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

try {
    // Check if users table exists and show its structure
    $result = $conn->query("DESCRIBE users");
    
    if (!$result) {
        echo "<h2>❌ Error checking users table structure</h2>";
        echo "<p>Error: " . $conn->error . "</p>";
    } else {
        echo "<h2>✅ Users Table Structure</h2>";
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr><th>Field</th><th>Type</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
        
        while ($row = $result->fetch_assoc()) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($row['Field']) . "</td>";
            echo "<td>" . htmlspecialchars($row['Type']) . "</td>";
            echo "<td>" . htmlspecialchars($row['Null']) . "</td>";
            echo "<td>" . htmlspecialchars($row['Key']) . "</td>";
            echo "<td>" . htmlspecialchars($row['Default'] ?? 'NULL') . "</td>";
            echo "<td>" . htmlspecialchars($row['Extra']) . "</td>";
            echo "</tr>";
        }
        echo "</table>";
        
        // Check if profile_photo column exists
        $hasProfilePhoto = false;
        $result->data_seek(0); // Reset result pointer
        while ($row = $result->fetch_assoc()) {
            if ($row['Field'] === 'profile_photo') {
                $hasProfilePhoto = true;
                break;
            }
        }
        
        if (!$hasProfilePhoto) {
            echo "<h3>⚠️ profile_photo column missing!</h3>";
            echo "<p>You need to add the profile_photo column to the users table:</p>";
            echo "<pre>ALTER TABLE users ADD COLUMN profile_photo VARCHAR(500) DEFAULT NULL;</pre>";
        } else {
            echo "<h3>✅ profile_photo column exists!</h3>";
        }
    }
    
} catch (Exception $e) {
    echo "<h2>❌ Database Error</h2>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}
?>
