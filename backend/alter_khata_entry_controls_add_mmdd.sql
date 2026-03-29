ALTER TABLE khata_entry_controls
ADD COLUMN previous_month_entry_cutoff_mmdd CHAR(5) DEFAULT NULL
AFTER previous_month_entry_cutoff_day;

