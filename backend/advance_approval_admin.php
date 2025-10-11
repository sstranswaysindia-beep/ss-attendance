<?php
declare(strict_types=1);

// Start session for admin authentication
session_start();

// Database connection
require_once __DIR__ . '/api/mobile/common.php';

// Simple admin authentication (you can enhance this)
$isAdmin = isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;

// Handle login
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if ($_POST['action'] === 'login') {
        $username = trim($_POST['username'] ?? '');
        $password = trim($_POST['password'] ?? '');
        
        // Simple hardcoded admin credentials (change these!)
        if ($username === 'admin' && $password === 'admin123') {
            $_SESSION['admin_logged_in'] = true;
            $isAdmin = true;
        } else {
            $loginError = 'Invalid credentials';
        }
    } elseif ($_POST['action'] === 'approve' || $_POST['action'] === 'reject') {
        if (!$isAdmin) {
            http_response_code(403);
            exit('Unauthorized');
        }
        
        $requestId = (int)($_POST['request_id'] ?? 0);
        $action = $_POST['action'];
        $comments = trim($_POST['comments'] ?? '');
        
        if ($requestId > 0) {
            try {
                global $conn, $mysqli, $con;
                $db = $conn instanceof mysqli ? $conn : ($mysqli instanceof mysqli ? $mysqli : ($con instanceof mysqli ? $con : null));
                
                if ($db) {
                    $status = $action === 'approve' ? 'approved' : 'rejected';
                    $stmt = $db->prepare("UPDATE advance_requests SET status = ?, admin_comments = ?, approved_at = NOW() WHERE id = ?");
                    $stmt->bind_param('si', $status, $comments, $requestId);
                    $stmt->execute();
                    $stmt->close();
                    
                    $successMessage = "Request {$action}d successfully!";
                }
            } catch (Exception $e) {
                $errorMessage = "Error updating request: " . $e->getMessage();
            }
        }
    } elseif ($_POST['action'] === 'logout') {
        session_destroy();
        header('Location: advance_approval_admin.php');
        exit;
    }
}

// Fetch advance requests
$requests = [];
if ($isAdmin) {
    try {
        global $conn, $mysqli, $con;
        $db = $conn instanceof mysqli ? $conn : ($mysqli instanceof mysqli ? $mysqli : ($con instanceof mysqli ? $con : null));
        
        if ($db) {
            $statusFilter = $_GET['status'] ?? 'all';
            $whereClause = '';
            $params = [];
            $types = '';
            
            if ($statusFilter !== 'all') {
                $whereClause = 'WHERE ar.status = ?';
                $params[] = $statusFilter;
                $types = 's';
            }
            
            $sql = "SELECT 
                        ar.id,
                        ar.driver_id,
                        ar.amount,
                        ar.purpose,
                        ar.status,
                        ar.requested_at,
                        ar.approved_at,
                        ar.admin_comments,
                        d.name as driver_name,
                        d.employee_id,
                        p.plant_name
                    FROM advance_requests ar
                    LEFT JOIN drivers d ON d.id = ar.driver_id
                    LEFT JOIN plants p ON p.id = d.plant_id
                    {$whereClause}
                    ORDER BY ar.requested_at DESC";
            
            $stmt = $db->prepare($sql);
            if (!empty($params)) {
                $stmt->bind_param($types, ...$params);
            }
            $stmt->execute();
            $result = $stmt->get_result();
            $requests = $result->fetch_all(MYSQLI_ASSOC);
            $stmt->close();
        }
    } catch (Exception $e) {
        $errorMessage = "Error fetching requests: " . $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Advance Request Approval - Admin Panel</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .admin-container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
        }
        .status-badge {
            font-size: 0.8rem;
            padding: 0.4rem 0.8rem;
            border-radius: 20px;
        }
        .status-pending { background-color: #fff3cd; color: #856404; }
        .status-approved { background-color: #d4edda; color: #155724; }
        .status-rejected { background-color: #f8d7da; color: #721c24; }
        .request-card {
            transition: all 0.3s ease;
            border: none;
            border-radius: 15px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.08);
        }
        .request-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
        }
        .btn-action {
            border-radius: 25px;
            padding: 0.5rem 1.5rem;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        .btn-approve {
            background: linear-gradient(45deg, #28a745, #20c997);
            border: none;
            color: white;
        }
        .btn-approve:hover {
            background: linear-gradient(45deg, #218838, #1ea085);
            transform: scale(1.05);
        }
        .btn-reject {
            background: linear-gradient(45deg, #dc3545, #e83e8c);
            border: none;
            color: white;
        }
        .btn-reject:hover {
            background: linear-gradient(45deg, #c82333, #d91a72);
            transform: scale(1.05);
        }
        .stats-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 15px;
            padding: 1.5rem;
            margin-bottom: 2rem;
        }
        .filter-tabs .nav-link {
            border-radius: 25px;
            margin: 0 0.25rem;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        .filter-tabs .nav-link.active {
            background: linear-gradient(45deg, #667eea, #764ba2);
            color: white;
        }
        .login-container {
            max-width: 400px;
            margin: 10vh auto;
        }
    </style>
</head>
<body>
    <div class="container-fluid py-4">
        <?php if (!$isAdmin): ?>
            <!-- Login Form -->
            <div class="login-container">
                <div class="admin-container p-4">
                    <div class="text-center mb-4">
                        <i class="fas fa-shield-alt fa-3x text-primary mb-3"></i>
                        <h2 class="fw-bold">Admin Login</h2>
                        <p class="text-muted">Advance Request Approval Panel</p>
                    </div>
                    
                    <?php if (isset($loginError)): ?>
                        <div class="alert alert-danger" role="alert">
                            <i class="fas fa-exclamation-triangle me-2"></i>
                            <?= htmlspecialchars($loginError) ?>
                        </div>
                    <?php endif; ?>
                    
                    <form method="POST">
                        <input type="hidden" name="action" value="login">
                        <div class="mb-3">
                            <label for="username" class="form-label">Username</label>
                            <input type="text" class="form-control" id="username" name="username" required>
                        </div>
                        <div class="mb-3">
                            <label for="password" class="form-label">Password</label>
                            <input type="password" class="form-control" id="password" name="password" required>
                        </div>
                        <button type="submit" class="btn btn-primary w-100 btn-action">
                            <i class="fas fa-sign-in-alt me-2"></i>Login
                        </button>
                    </form>
                    
                    <div class="mt-4 text-center">
                        <small class="text-muted">
                            <strong>Default Credentials:</strong><br>
                            Username: admin<br>
                            Password: admin123
                        </small>
                    </div>
                </div>
            </div>
        <?php else: ?>
            <!-- Admin Dashboard -->
            <div class="admin-container p-4">
                <!-- Header -->
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <div>
                        <h1 class="fw-bold text-primary">
                            <i class="fas fa-clipboard-check me-2"></i>
                            Advance Request Approval
                        </h1>
                        <p class="text-muted mb-0">Manage employee advance requests</p>
                    </div>
                    <form method="POST" class="d-inline">
                        <input type="hidden" name="action" value="logout">
                        <button type="submit" class="btn btn-outline-danger">
                            <i class="fas fa-sign-out-alt me-2"></i>Logout
                        </button>
                    </form>
                </div>

                <!-- Alerts -->
                <?php if (isset($successMessage)): ?>
                    <div class="alert alert-success alert-dismissible fade show" role="alert">
                        <i class="fas fa-check-circle me-2"></i>
                        <?= htmlspecialchars($successMessage) ?>
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                <?php endif; ?>

                <?php if (isset($errorMessage)): ?>
                    <div class="alert alert-danger alert-dismissible fade show" role="alert">
                        <i class="fas fa-exclamation-triangle me-2"></i>
                        <?= htmlspecialchars($errorMessage) ?>
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                <?php endif; ?>

                <!-- Statistics -->
                <div class="row mb-4">
                    <div class="col-md-3">
                        <div class="stats-card text-center">
                            <h3 class="fw-bold"><?= count(array_filter($requests, fn($r) => $r['status'] === 'pending')) ?></h3>
                            <p class="mb-0">Pending Requests</p>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="stats-card text-center">
                            <h3 class="fw-bold"><?= count(array_filter($requests, fn($r) => $r['status'] === 'approved')) ?></h3>
                            <p class="mb-0">Approved</p>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="stats-card text-center">
                            <h3 class="fw-bold"><?= count(array_filter($requests, fn($r) => $r['status'] === 'rejected')) ?></h3>
                            <p class="mb-0">Rejected</p>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="stats-card text-center">
                            <h3 class="fw-bold"><?= count($requests) ?></h3>
                            <p class="mb-0">Total Requests</p>
                        </div>
                    </div>
                </div>

                <!-- Filter Tabs -->
                <ul class="nav nav-pills filter-tabs mb-4">
                    <li class="nav-item">
                        <a class="nav-link <?= ($_GET['status'] ?? 'all') === 'all' ? 'active' : '' ?>" 
                           href="?status=all">All Requests</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link <?= ($_GET['status'] ?? '') === 'pending' ? 'active' : '' ?>" 
                           href="?status=pending">Pending</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link <?= ($_GET['status'] ?? '') === 'approved' ? 'active' : '' ?>" 
                           href="?status=approved">Approved</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link <?= ($_GET['status'] ?? '') === 'rejected' ? 'active' : '' ?>" 
                           href="?status=rejected">Rejected</a>
                    </li>
                </ul>

                <!-- Requests List -->
                <div class="row">
                    <?php if (empty($requests)): ?>
                        <div class="col-12">
                            <div class="text-center py-5">
                                <i class="fas fa-inbox fa-3x text-muted mb-3"></i>
                                <h4 class="text-muted">No requests found</h4>
                                <p class="text-muted">No advance requests match the current filter.</p>
                            </div>
                        </div>
                    <?php else: ?>
                        <?php foreach ($requests as $request): ?>
                            <div class="col-md-6 col-lg-4 mb-4">
                                <div class="card request-card h-100">
                                    <div class="card-body">
                                        <div class="d-flex justify-content-between align-items-start mb-3">
                                            <h5 class="card-title fw-bold">
                                                <?= htmlspecialchars($request['driver_name'] ?? 'Unknown Driver') ?>
                                            </h5>
                                            <span class="status-badge status-<?= $request['status'] ?>">
                                                <?= ucfirst($request['status']) ?>
                                            </span>
                                        </div>
                                        
                                        <div class="mb-3">
                                            <div class="row">
                                                <div class="col-6">
                                                    <small class="text-muted">Employee ID</small>
                                                    <div class="fw-semibold"><?= htmlspecialchars($request['employee_id'] ?? 'N/A') ?></div>
                                                </div>
                                                <div class="col-6">
                                                    <small class="text-muted">Plant</small>
                                                    <div class="fw-semibold"><?= htmlspecialchars($request['plant_name'] ?? 'N/A') ?></div>
                                                </div>
                                            </div>
                                        </div>
                                        
                                        <div class="mb-3">
                                            <small class="text-muted">Amount</small>
                                            <div class="h4 text-primary fw-bold">₹<?= number_format($request['amount'], 2) ?></div>
                                        </div>
                                        
                                        <div class="mb-3">
                                            <small class="text-muted">Purpose</small>
                                            <div class="fw-semibold"><?= htmlspecialchars($request['purpose']) ?></div>
                                        </div>
                                        
                                        <div class="mb-3">
                                            <small class="text-muted">Requested On</small>
                                            <div class="fw-semibold">
                                                <?= date('M d, Y H:i', strtotime($request['requested_at'])) ?>
                                            </div>
                                        </div>
                                        
                                        <?php if ($request['approved_at']): ?>
                                            <div class="mb-3">
                                                <small class="text-muted">Processed On</small>
                                                <div class="fw-semibold">
                                                    <?= date('M d, Y H:i', strtotime($request['approved_at'])) ?>
                                                </div>
                                            </div>
                                        <?php endif; ?>
                                        
                                        <?php if ($request['admin_comments']): ?>
                                            <div class="mb-3">
                                                <small class="text-muted">Admin Comments</small>
                                                <div class="fw-semibold"><?= htmlspecialchars($request['admin_comments']) ?></div>
                                            </div>
                                        <?php endif; ?>
                                        
                                        <?php if ($request['status'] === 'pending'): ?>
                                            <div class="mt-auto">
                                                <form method="POST" class="d-inline">
                                                    <input type="hidden" name="action" value="approve">
                                                    <input type="hidden" name="request_id" value="<?= $request['id'] ?>">
                                                    <div class="mb-2">
                                                        <textarea class="form-control form-control-sm" 
                                                                  name="comments" 
                                                                  placeholder="Add comments (optional)" 
                                                                  rows="2"></textarea>
                                                    </div>
                                                    <div class="d-flex gap-2">
                                                        <button type="submit" class="btn btn-approve btn-action flex-fill">
                                                            <i class="fas fa-check me-1"></i>Approve
                                                        </button>
                                                        <button type="button" class="btn btn-reject btn-action flex-fill" 
                                                                onclick="rejectRequest(<?= $request['id'] ?>)">
                                                            <i class="fas fa-times me-1"></i>Reject
                                                        </button>
                                                    </div>
                                                </form>
                                            </div>
                                        <?php endif; ?>
                                    </div>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
    </div>

    <!-- Reject Modal -->
    <div class="modal fade" id="rejectModal" tabindex="-1">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Reject Advance Request</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form method="POST" id="rejectForm">
                    <div class="modal-body">
                        <input type="hidden" name="action" value="reject">
                        <input type="hidden" name="request_id" id="rejectRequestId">
                        <div class="mb-3">
                            <label for="rejectComments" class="form-label">Reason for Rejection</label>
                            <textarea class="form-control" id="rejectComments" name="comments" rows="4" 
                                      placeholder="Please provide a reason for rejecting this request..." required></textarea>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                        <button type="submit" class="btn btn-reject btn-action">
                            <i class="fas fa-times me-1"></i>Reject Request
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function rejectRequest(requestId) {
            document.getElementById('rejectRequestId').value = requestId;
            document.getElementById('rejectComments').value = '';
            new bootstrap.Modal(document.getElementById('rejectModal')).show();
        }
        
        // Auto-refresh every 30 seconds for pending requests
        <?php if (($_GET['status'] ?? '') === 'pending' || ($_GET['status'] ?? 'all') === 'all'): ?>
        setTimeout(() => {
            location.reload();
        }, 30000);
        <?php endif; ?>
    </script>
</body>
</html>
