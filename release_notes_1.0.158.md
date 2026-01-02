Release 1.0.158
----------------
- Khata Book (You Gave): if category is `DA` or `MEDICAL`, Driver selection is mandatory (same as uniform flow).
- Khata Book (Edit Transaction): category list is restricted based on existing transaction linkage:
  - if `vehicleId` is present → show only vehicle-mandatory categories
  - else if `counterpartyDriverId` is present → show only driver-applicable categories (from You Gave rules)
  - else (no vehicle + no driver) → show only the current category (e.g. EXTRA/MISCELLANEOUS)
- Android: block system Font Size / Display Size from affecting app UI scaling.



