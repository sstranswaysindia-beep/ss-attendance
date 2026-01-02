# Safety Section Analysis - Supervisor Dashboard

## Overview
The Safety section in the supervisor dashboard provides access to various safety-related modules and workflows. It's accessible from the Quick Links section of the supervisor dashboard and navigates to a dedicated Safety Hub screen.

## Location in Supervisor Dashboard

### Entry Point
- **File**: `lib/features/dashboard/supervisor_dashboard_screen.dart`
- **Lines**: 1135-1147
- **UI Component**: `HoverListTile` with health_and_safety icon
- **Visibility**: Only visible for users with role `driver` or `supervisor`
- **Navigation**: Opens `SafetyHubScreen` when tapped

```dart
if (widget.user.role == UserRole.driver ||
    widget.user.role == UserRole.supervisor) ...[
  const Divider(height: 0),
  HoverListTile(
    leading: const Icon(Icons.health_and_safety),
    title: const Text('Safety'),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SafetyHubScreen(user: widget.user),
      ),
    ),
  ),
],
```

## Safety Hub Screen

### File Location
- **File**: `lib/features/safety/safety_hub_screen.dart`
- **Purpose**: Main entry point for all safety modules

### Architecture

#### 1. **State Management**
- Uses `StatefulWidget` with `_SafetyHubScreenState`
- Initializes `SafetyRepository` with current user
- Fetches modules on initialization via `_modulesFuture`

#### 2. **Module Fetching**
- **API Endpoint**: `https://sstranswaysindia.com/api/safety/modules.php`
- **Backend File**: `backend/api/safety/modules.php`
- **Fallback**: If API returns empty, defaults to 4 hardcoded modules:
  - Tyre Checklist
  - In-Cab
  - Spot Audit
  - Training

#### 3. **UI Structure**
- **Layout**: GridView with 2 columns (`crossAxisCount: 2`)
- **Card Design**: Custom gradient cards with icons and descriptions
- **States Handled**:
  - Loading: Shows `CircularProgressIndicator`
  - Error: Shows `_SafetyError` widget with retry button
  - Empty: Shows `_SafetyEmptyState` widget
  - Success: Displays module cards in grid

### Available Safety Modules

#### 1. **Tyre Checklist** (`tyre_checklist`)
- **Icon**: `Icons.build_circle_outlined`
- **Color**: `#1C7ED6` (Blue)
- **Gradient**: White to light blue (`#E6F3FF`)
- **Subtitle**: "Daily tyre inspection checklist"
- **Navigation**: Opens `TyreInstructionsScreen`
- **Features**:
  - Daily tyre inspection workflow
  - PSI pressure checks (min: 120, max: 130)
  - 8 checkpoint inspection process
  - Photo capture capability
  - Vehicle selection and tracking

#### 2. **In-Cab Assessment** (`incab`)
- **Icon**: `Icons.event_seat`
- **Color**: `#00A896` (Teal)
- **Gradient**: White to light teal (`#DFF5FF`)
- **Subtitle**: "In-cab assessment"
- **Navigation**: Opens `InCabAssessmentScreen`
- **Features**:
  - Multi-step assessment form
  - Driver and vehicle selection
  - Plant directory integration
  - Section-based questions
  - Date, weather, and location tracking

#### 3. **Spot Audit** (`spot_audit`)
- **Icon**: `Icons.fact_check`
- **Color**: `#F77F00` (Orange)
- **Gradient**: White to light blue (`#E3F2FD`)
- **Subtitle**: "Random safety audits"
- **Navigation**: Opens `SpotAuditWizardScreen`
- **Features**:
  - Random safety audit workflow
  - Plant, driver, and vehicle selection
  - Assessment date tracking
  - Highlights and action plans
  - Section-based audit structure

#### 4. **Training** (`training`)
- **Icon**: `Icons.school`
- **Color**: `#9D4EDD` (Purple)
- **Gradient**: White to light purple (`#DDEBFF`)
- **Subtitle**: "Learning modules"
- **Navigation**: Opens `SafetyTrainingScreen`
- **Features**:
  - Audio-based training modules
  - Progress tracking (position_seconds, completed)
  - Sequential unlocking (must complete previous to unlock next)
  - Transcript support
  - Duration tracking

## Data Flow

### Repository Layer
- **File**: `lib/core/services/safety_repository.dart`
- **Base URI**: `https://sstranswaysindia.com/api/safety/`
- **Authentication**: Includes user role, userId, driverId, plantId, and supervisedPlantIds in query parameters

### Key Methods
1. `fetchModules()` - Gets available safety modules
2. `fetchVehicles()` - Gets vehicles for inspections (scope: 'all' for supervisors)
3. `fetchPlantDirectory()` - Gets plant directory entries
4. `fetchInCabQuestions()` - Gets in-cab assessment questions
5. `fetchTrainingModules()` - Gets training modules with progress
6. `submitInCabAssessment()` - Submits in-cab assessment
7. `submitSpotAudit()` - Submits spot audit
8. `saveTrainingProgress()` - Saves training progress

### Models
- **File**: `lib/core/models/safety_models.dart`
- **Key Classes**:
  - `SafetyModule` - Module definition (key, label)
  - `SafetyVehicle` - Vehicle information with inspection status
  - `TyreInstructions` - Tyre inspection instructions
  - `TyreCheckpoint` - Individual checkpoint data
  - `TyreCheckpointResult` - Enum (acceptable, caution, non_acceptable)

## Backend API Endpoints

### Base Path
`/api/safety/`

### Key Endpoints
1. **modules.php** - Returns available safety modules
2. **vehicles.php** - Returns vehicles (supports scope filtering)
3. **plant_directory.php** - Returns plant directory
4. **incab_questions.php** - Returns in-cab assessment questions
5. **incab_save.php** - Saves in-cab assessment
6. **spot_audit_save.php** - Saves spot audit
7. **training_modules.php** - Returns training modules with progress
8. **training_progress_save.php** - Saves training progress

### Authentication Context
The backend uses `safety_user_context()` helper function which extracts:
- User ID (from userId or driverId)
- Role (driver, supervisor, admin)
- Plant ID
- Supervised Plant IDs (for supervisors)

## User Experience Flow

### Supervisor Access Flow
1. Supervisor opens dashboard
2. Scrolls to "Quick Links" section
3. Taps "Safety" tile (with health_and_safety icon)
4. Safety Hub screen opens
5. Grid of 4 safety modules displayed
6. Taps desired module card
7. Module-specific screen opens

### Module-Specific Flows

#### Tyre Checklist Flow
1. Select vehicle from list
2. Start inspection (creates inspection record)
3. For each tyre position:
   - Check 8 checkpoints
   - Enter PSI value
   - Capture photo (optional)
   - Add remarks if needed
4. Submit inspection

#### In-Cab Assessment Flow
1. Step 1: Select driver, vehicle, plant, date, weather, location
2. Step 2-5: Answer section-based questions
3. Step 6: Review and submit

#### Spot Audit Flow
1. Select plant, driver, vehicle
2. Fill assessment details
3. Complete sections
4. Add highlights, action plan, target date
5. Submit audit

#### Training Flow
1. View list of training modules
2. Modules locked until previous completed
3. Open module to play audio
4. Progress auto-saved
5. Complete module to unlock next

## Design Patterns

### 1. **Repository Pattern**
- Centralized API communication via `SafetyRepository`
- Dependency injection of user context
- Error handling and fallback mechanisms

### 2. **FutureBuilder Pattern**
- Async data loading with loading/error/success states
- Clean separation of concerns

### 3. **Navigation Pattern**
- MaterialPageRoute for screen transitions
- User context passed to child screens

### 4. **State Management**
- Local state management with setState
- Future-based async operations

## Error Handling

### Client-Side
- Try-catch blocks in repository methods
- User-friendly error messages via `showAppToast`
- Retry mechanisms in error widgets
- Fallback data when API fails

### Server-Side
- HTTP status code checking (>= 300 considered error)
- JSON response validation (`ok` or `status` fields)
- Exception messages propagated to client

## Security Considerations

### Authentication
- User context passed in query parameters
- Role-based access control
- Plant-based data filtering for supervisors

### Data Validation
- Input validation on forms
- Type checking in model parsing
- Null safety throughout

## Performance Optimizations

1. **Lazy Loading**: Modules fetched only when Safety Hub opens
2. **Caching**: Future results cached until refresh
3. **Image Handling**: Base64 encoding for photos
4. **Progress Tracking**: Incremental saves for training

## Dependencies

### Flutter Packages
- `http` - API communication
- `intl` - Date formatting
- `google_fonts` - Typography
- `collection` - Utility functions

### Custom Widgets
- `AppGradientBackground` - Consistent background
- `AppToast` - Toast notifications
- `ProfilePhotoWidget` - User avatars

## Potential Improvements

1. **Offline Support**: Cache modules and enable offline access
2. **Progress Indicators**: Show completion status on module cards
3. **Notifications**: Alert supervisors of pending assessments
4. **Analytics**: Track module usage and completion rates
5. **Search/Filter**: Add search for vehicles/plants in large lists
6. **Bulk Operations**: Allow multiple vehicle inspections
7. **Export**: PDF/Excel export for audit reports
8. **Dashboard Widgets**: Show safety metrics on main dashboard

## Testing Considerations

### Unit Tests Needed
- Repository methods
- Model parsing
- State management

### Integration Tests Needed
- API endpoint responses
- Navigation flows
- Form submissions

### UI Tests Needed
- Module card interactions
- Error state handling
- Loading states

## Related Files

### Frontend
- `lib/features/safety/safety_hub_screen.dart` - Main hub
- `lib/features/safety/tyre_instructions_screen.dart` - Tyre checklist
- `lib/features/safety/incab_assessment_screen.dart` - In-cab assessment
- `lib/features/safety/spot_audit_wizard_screen.dart` - Spot audit
- `lib/features/safety/training/training_screen.dart` - Training list
- `lib/core/services/safety_repository.dart` - API layer
- `lib/core/models/safety_models.dart` - Data models

### Backend
- `backend/api/safety/modules.php` - Modules endpoint
- `backend/api/safety/vehicles.php` - Vehicles endpoint
- `backend/api/safety/helpers.php` - Helper functions
- `backend/api/safety/incab_questions.php` - In-cab questions
- `backend/api/safety/incab_save.php` - In-cab save
- `backend/api/safety/training_modules.php` - Training modules
- `backend/api/safety/training_progress_save.php` - Progress save

## Summary

The Safety section in the supervisor dashboard is a comprehensive safety management system with four main modules:
1. **Tyre Checklist** - Daily vehicle tyre inspections
2. **In-Cab Assessment** - Driver in-cab safety assessments
3. **Spot Audit** - Random safety audits
4. **Training** - Audio-based safety training modules

The implementation follows Flutter best practices with proper separation of concerns, error handling, and user experience considerations. The system supports role-based access and plant-based data filtering for supervisors.


