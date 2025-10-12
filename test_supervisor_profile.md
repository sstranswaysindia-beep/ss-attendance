# Supervisor Profile Test Guide

## 🎯 What's New:

### **1. Separate Profile Screen for Supervisors Without Driver ID**
- **New File**: `SupervisorProfileScreen` - dedicated profile for supervisors without driver_id
- **Data Source**: Pulls from `users` table instead of `drivers` table
- **Smart Navigation**: Automatically detects supervisor type and routes correctly

### **2. Backend API for User Profile Data**
- **New File**: `get_user_profile.php` - fetches user data from users table
- **Features**: Includes supervised plants, account info, personal details

## 📱 How to Test:

### **Step 1: Upload Backend File**
Upload this file to your server:
```
backend/api/mobile/get_user_profile.php
```

### **Step 2: Install Updated APK**
```
/Users/neerajsachan/SS Transways India/sstranswaysindia/build/app/outputs/flutter-apk/app-release.apk
```

### **Step 3: Test Different Supervisor Types**

#### **Test A: Supervisor WITH driver_id**
1. Login with a supervisor account that has driver_id
2. Go to Profile → Should see "Driver Profile" (existing functionality)
3. Profile photo upload should work normally

#### **Test B: Supervisor WITHOUT driver_id**
1. Login with a supervisor account that has NO driver_id
2. Go to Profile → Should see "Supervisor Profile" (NEW functionality)
3. Should show data from users table:
   - User ID, Username, Role
   - Full Name, Email, Phone (from users table)
   - Account Created, Last Login, Password Status
   - Supervised Plants list

### **Step 4: Verify Profile Photo Handling**
- **Supervisors with driver_id**: Photo upload works (unchanged)
- **Supervisors without driver_id**: Shows "Profile photo upload for supervisors is being developed"

## 🔍 What to Look For:

### **NEW Supervisor Profile Screen Should Show:**
- ✅ **Title**: "Supervisor Profile" (not "Driver Profile")
- ✅ **Account Information Section**: User ID, Username, Role, Supervised Plants
- ✅ **Personal Details Section**: Full Name, Email, Phone from users table
- ✅ **System Information Section**: Account Created, Last Login, Password Status
- ✅ **Info Box**: Blue box explaining this is a supervisor account
- ✅ **Profile Photo**: Shows development message instead of upload

### **Existing Driver Profile Screen (for supervisors with driver_id):**
- ✅ **Title**: "Driver Profile"
- ✅ **Driver Information**: Employee ID, Plant, Vehicle, etc.
- ✅ **Profile Photo**: Upload functionality works normally

## 🎯 Expected Behavior:

### **Automatic Detection:**
- App automatically detects if supervisor has driver_id
- Routes to correct profile screen based on supervisor type
- No manual selection needed

### **Data Sources:**
- **Supervisors with driver_id**: Data from drivers table (unchanged)
- **Supervisors without driver_id**: Data from users table (NEW)

## 🚨 If No Changes Visible:

1. **Uninstall old app** completely
2. **Install fresh APK** from the build folder
3. **Upload backend file** `get_user_profile.php`
4. **Test with different supervisor accounts** (with and without driver_id)
5. **Check console logs** for any errors

## 📊 Test Results:

After testing, you should see:
- ✅ **Two different profile screens** based on supervisor type
- ✅ **Correct data sources** (users vs drivers table)
- ✅ **Proper navigation** (automatic detection)
- ✅ **Profile photo handling** (working vs development message)

Build completed: $(date)
APK size: 61.9MB
