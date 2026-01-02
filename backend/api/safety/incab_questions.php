<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$response = [
    'status' => 'ok',
    'sections' => [
        [
            'key' => 'pre_drive',
            'title' => 'ड्राइव शुरू करने से पहले',
            'items' => [
                ['code' => 'A', 'text' => 'वाहन के चारों ओर घूमना', 'options' => ['yes', 'no']],
                ['code' => 'B', 'text' => 'चढ़ते/उतरते समय तीन बिंदु संपर्क नियम का उपयोग', 'options' => ['yes', 'no']],
                ['code' => 'C', 'text' => 'सीट बेल्ट पहनना', 'options' => ['yes', 'no']],
                ['code' => 'D', 'text' => 'सीट बेल्ट को एडजस्ट करना', 'options' => ['yes', 'no']],
                ['code' => 'E', 'text' => 'दर्पण को एडजस्ट या जाँचना', 'options' => ['yes', 'no']],
            ],
        ],
        [
            'key' => 'distance',
            'title' => 'दरूरी बनाए रखना',
            'items' => [
                ['code' => 'DIST_1', 'text' => 'हमेशा कम से कम "दो-सेकंड" दूरी बनाए रखना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_2', 'text' => 'आगे कोई दूसरी कार आने पर तुरंत सुरक्षित दूरी पर लौट जाना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_3', 'text' => 'टेलगेटर्स से बचते हुए दूरी बढ़ा देना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_4', 'text' => 'खराब मौसम / सड़क स्थिति में दूरी चार से आठ सेकंड करना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_5', 'text' => 'रोड-वे पर लो-बीम हेडलाइट्स का उपयोग।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_6', 'text' => 'लेन बदलते समय इंडिकेटर का उपयोग।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_7', 'text' => 'कच्ची सड़क पर गति कम करना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_8', 'text' => 'धीमी गति वाले वाहन को सावधानी से ओवरटेक करना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'DIST_9', 'text' => 'चौराहे या भारी ट्रैफिक के पास पहुँचते समय सतर्कता।', 'options' => ['positive','needs_improvement','not_observed']],
            ],
        ],
        [
            'key' => 'scanning',
            'title' => '360° स्कैनिंग',
            'items' => [
                ['code' => 'SCAN_1', 'text' => 'वाहन के आगे, पीछे और दोनों तरफ स्कैन करना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'SCAN_2', 'text' => 'लेन बदलने, ब्रेक लगाने, वाहन रोकने या फिर से चलाने के दौरान रियर व साइड-व्यू मिरर देखना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'SCAN_3', 'text' => 'आगे के खतरों के लिए ब्रेक लगाने या लेन बदलने की अग्रिम योजना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'SCAN_4', 'text' => 'वाहन रोकने पर भी 270° स्कैनिंग जारी रखना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'SCAN_5', 'text' => 'रिवर्स करते समय 270° स्कैन और हेल्पर की सहायता लेना, पीछे मुड़कर देखना।', 'options' => ['positive','needs_improvement','not_observed']],
            ],
        ],
        [
            'key' => 'braking',
            'title' => 'ब्रेकिंग स्किल',
            'items' => [
                ['code' => 'BRAKE_1', 'text' => 'संभावित समस्या या खतरे पर “अचानक ब्रेक” का नियंत्रित उपयोग।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'BRAKE_2', 'text' => 'सामान्य स्थिति में वाहन को आराम से रोकने के लिए स्मूथ ब्रेकिंग।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'BRAKE_3', 'text' => 'वाहन रोकने के लिए सड़क के बाएँ ओर वाहन ले जाना।', 'options' => ['positive','needs_improvement','not_observed']],
                ['code' => 'BRAKE_4', 'text' => 'सड़क किनारे वाहन रुकने पर हज़ार्ड लाइट का उपयोग।', 'options' => ['positive','needs_improvement','not_observed']],
            ],
        ],
    ],
    'options_map' => [
        'yes_no' => ['yes', 'no'],
        'rating' => ['positive', 'needs_improvement', 'not_observed'],
    ],
];

echo json_encode($response);
