<?php
declare(strict_types=1);

require __DIR__ . '/../bootstrap.php';

$psiMin = 120.0;
$psiMax = 130.0;

if (isset($conn) && $conn instanceof \mysqli) {
    try {
        $stmt = $conn->prepare(
            "SELECT setting_key, setting_value
             FROM system_settings
             WHERE setting_key IN ('SAFETY_TYRE_PSI_MIN', 'SAFETY_TYRE_PSI_MAX')"
        );
        if ($stmt) {
            $stmt->execute();
            $res = $stmt->get_result();
            while ($row = $res->fetch_assoc()) {
                $value = $row['setting_value'] ?? null;
                if ($value !== null) {
                    if ($row['setting_key'] === 'SAFETY_TYRE_PSI_MIN') {
                        $psiMin = (float)$value;
                    } elseif ($row['setting_key'] === 'SAFETY_TYRE_PSI_MAX') {
                        $psiMax = (float)$value;
                    }
                }
            }
            $stmt->close();
        }
    } catch (Throwable $e) {
        // ignore and fall back to defaults
    }
}

$checkpoints = [
    [
        'no' => 1,
        'text_hi' => 'टायर में कील / पत्थर के लिए जाँच।',
        'text_en' => 'Check visually for Nails / stones.',
    ],
    [
        'no' => 2,
        'text_hi' => 'संभावित लीक (वाल्व कैप्स / एक्सटेंशन वाल्व) के लिए जाँच।',
        'text_en' => 'Check visually for possible leakage (valve caps / extension valves).',
    ],
    [
        'no' => 3,
        'text_hi' => 'टायर में हवा का दबाव जाँच।',
        'text_en' => 'Check air pressure in the tyre.',
    ],
    [
        'no' => 4,
        'text_hi' => 'फुलाव और कट्स के लिए टायर की साइडवॉल्स की जाँच।',
        'text_en' => 'Check visually for bumps and cuts on tyre sidewalls.',
    ],
    [
        'no' => 5,
        'text_hi' => 'अगर अनियमित घिसाव है — वाहन के सस्पेंशन / रिम के नट्स की जाँच करें।',
        'text_en' => 'If irregular wear—check suspension / nuts on rims.',
    ],
    [
        'no' => 6,
        'text_hi' => 'टायर की ट्रेड गहराई 75% चौड़ाई और परिधि पर जाँचें।',
        'text_en' => 'Check tread depth ~75% across width and circumference.',
    ],
    [
        'no' => 7,
        'text_hi' => 'एक ही धुरी/एक्सल पर एक ही प्रकार/आकार/कंपनी के टायर इस्तेमाल हों।',
        'text_en' => 'Same manufacturer/type/size/service description/wear on same axle.',
    ],
    [
        'no' => 8,
        'text_hi' => 'दिशात्मक टायर विपरीत दिशा में न लगाएँ।',
        'text_en' => 'Do not use directional tyres in opposite direction.',
    ],
];

apiRespond(200, [
    'ok' => true,
    'checkpoints' => $checkpoints,
    'psi' => [
        'min' => $psiMin,
        'max' => $psiMax,
    ],
]);
