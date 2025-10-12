<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

try {
    // Check if profile_photo column exists
    $result = $conn->query("SHOW COLUMNS FROM users LIKE 'profile_photo'");
    
    if ($result->num_rows > 0) {
        echo "<h2>✅ profile_photo column already exists</h2>";
        echo "<p>The users table already has a profile_photo column.</p>";
    } else {
        echo "<h2>⚠️ Adding profile_photo column...</h2>";
        
        // Add the profile_photo column
        $sql = "ALTER TABLE users ADD COLUMN profile_photo VARCHAR(500) DEFAULT NULL";
        
        if ($conn->query($sql)) {
            echo "<h3>✅ Successfully added profile_photo column!</h3>";
            echo "<p>The profile_photo column has been added to the users table.</p>";
        } else {
            echo "<h3>❌ Failed to add profile_photo column</h3>";
            echo "<p>Error: " . $conn->error . "</p>";
        }
    }
    
    // Show updated table structure
    echo "<h3>Updated Users Table Structure:</h3>";
    $result = $conn->query("DESCRIBE users");
    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
    echo "<tr><th>Field</th><th>Type</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
    
    while ($row = $result->fetch_assoc()) {
        $isProfilePhoto = $row['Field'] === 'profile_photo' ? ' style="background-color: #90EE90;"' : '';
        echo "<tr$isProfilePhoto>";
        echo "<td>" . htmlspecialchars($row['Field']) . "</td>";
        echo "<td>" . htmlspecialchars($row['Type']) . "</td>";
        echo "<td>" . htmlspecialchars($row['Null']) . "</td>";
        echo "<td>" . htmlspecialchars($row['Key']) . "</td>";
        echo "<td>" . htmlspecialchars($row['Default'] ?? 'NULL') . "</td>";
        echo "<td>" . htmlspecialchars($row['Extra']) . "</td>";
        echo "</tr>";
    }
    echo "</table>";
    
} catch (Exception $e) {
    echo "<h2>❌ Database Error</h2>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}
?>
