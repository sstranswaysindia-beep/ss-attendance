// app.js
import express from 'express';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import mysql from 'mysql2/promise';

dotenv.config();
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  timezone: 'Z'
});

// Utility
const ddmmyyyy = (d) => {
  const dt = new Date(d);
  const dd = String(dt.getDate()).padStart(2,'0');
  const mm = String(dt.getMonth()+1).padStart(2,'0');
  const yyyy = dt.getFullYear();
  return `${dd}-${mm}-${yyyy}`;
};

// --- META: drivers, helpers, vehicles, customer suggestions
app.get('/api/meta', async (req, res) => {
  try {
    const conn = await pool.getConnection();
    try {
      const [drivers]  = await conn.query(
        "SELECT id, name FROM drivers WHERE status='Active' AND (role='driver' OR role IS NULL) ORDER BY name"
      );
      const [helpers]  = await conn.query(
        "SELECT id, name FROM drivers WHERE status='Active' AND role='helper' ORDER BY name"
      );
      const [vehicles] = await conn.query(
        "SELECT id, vehicle_no FROM vehicles ORDER BY vehicle_no"
      );
      const [customers] = await conn.query(
        "SELECT DISTINCT customer_name AS name FROM trip_customers ORDER BY name"
      );
      res.json({ drivers, helpers, vehicles, customers });
    } finally { conn.release(); }
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Failed to load meta' });
  }
});

// --- CREATE ONGOING TRIP
app.post('/api/trips', async (req, res) => {
  const {
    vehicle_id, start_date, start_km, driver_ids, helper_id, customer_names, note
  } = req.body;

  if (!vehicle_id) return res.status(400).json({ error: 'vehicle_id required' });
  if (!start_date) return res.status(400).json({ error: 'start_date required' });
  if (start_km == null || start_km === '') return res.status(400).json({ error: 'start_km required' });
  if (!Array.isArray(driver_ids) || driver_ids.length === 0) {
    return res.status(400).json({ error: 'At least one driver is mandatory' });
  }
  if (!Array.isArray(customer_names) || customer_names.length === 0) {
    return res.status(400).json({ error: 'At least one customer is mandatory' });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [ins] = await conn.query(
      `INSERT INTO trips (vehicle_id, start_date, start_km, status, note)
       VALUES (?, ?, ?, 'ongoing', ?)`,
      [vehicle_id, start_date, start_km, note ?? null]
    );
    const tripId = ins.insertId;

    // drivers
    for (const d of driver_ids) {
      await conn.query(`INSERT INTO trip_drivers (trip_id, driver_id) VALUES (?,?)`, [tripId, d]);
    }

    // helper
    if (helper_id) {
      await conn.query(
        `INSERT INTO trip_helper (trip_id, helper_id) VALUES (?, ?)`,
        [tripId, helper_id]
      );
    }

    // customers
    for (const cname of customer_names) {
      await conn.query(
        `INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)`,
        [tripId, String(cname).trim()]
      );
    }

    await conn.commit();
    res.json({ ok: true, trip_id: tripId });
  } catch (e) {
    await pool.query('ROLLBACK');
    console.error(e);
    res.status(500).json({ error: 'Failed to create trip' });
  } finally {
    conn.release();
  }
});

// --- END TRIP
app.patch('/api/trips/:id/end', async (req, res) => {
  const { id } = req.params;
  const { end_date, end_km } = req.body;

  if (!end_date) return res.status(400).json({ error: 'end_date required' });
  if (end_km == null || end_km === '') return res.status(400).json({ error: 'end_km required' });

  const conn = await pool.getConnection();
  try {
    const [rows] = await conn.query(`SELECT start_km FROM trips WHERE id=?`, [id]);
    if (rows.length === 0) return res.status(404).json({ error: 'Trip not found' });

    const start_km = rows[0].start_km;
    if (Number(end_km) < Number(start_km)) {
      return res.status(400).json({ error: 'end_km cannot be less than start_km' });
    }

    await conn.query(
      `UPDATE trips
       SET end_date=?, end_km=?, status='ended'
       WHERE id=?`,
      [end_date, end_km, id]
    );

    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Failed to end trip' });
  } finally { conn.release(); }
});

// --- LIST TRIPS for a vehicle (latest first)
app.get('/api/trips', async (req, res) => {
  const { vehicle_id } = req.query;
  if (!vehicle_id) return res.status(400).json({ error: 'vehicle_id query param required' });

  try {
    const conn = await pool.getConnection();
    try {
      const [rows] = await conn.query(
        `SELECT t.id, t.vehicle_id, v.vehicle_no,
                t.start_date, t.start_km, t.status, t.note,
                t.end_date, t.end_km, t.total_km,
                (SELECT GROUP_CONCAT(d.name ORDER BY d.name SEPARATOR ', ')
                   FROM trip_drivers td
                   JOIN drivers d ON d.id=td.driver_id
                  WHERE td.trip_id=t.id) AS drivers,
                (SELECT d2.name FROM trip_helper th
                   JOIN drivers d2 ON d2.id=th.helper_id
                  WHERE th.trip_id=t.id) AS helper,
                (SELECT GROUP_CONCAT(tc.customer_name ORDER BY tc.customer_name SEPARATOR ', ')
                   FROM trip_customers tc
                  WHERE tc.trip_id=t.id) AS customers
         FROM trips t
         JOIN vehicles v ON v.id=t.vehicle_id
         WHERE t.vehicle_id=?
         ORDER BY COALESCE(t.end_date, t.start_date) DESC, t.id DESC
         LIMIT 200`,
        [vehicle_id]
      );

      // format dates dd-mm-yyyy for frontend convenience
      const out = rows.map(r => ({
        ...r,
        start_date_fmt: r.start_date ? ddmmyyyy(r.start_date) : null,
        end_date_fmt: r.end_date ? ddmmyyyy(r.end_date) : null
      }));

      res.json(out);
    } finally { conn.release(); }
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Failed to fetch trips' });
  }
});

// --- DELETE trip
app.delete('/api/trips/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [r] = await pool.query(`DELETE FROM trips WHERE id=?`, [id]);
    if (r.affectedRows === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Failed to delete trip' });
  }
});

// --- Serve SPA
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const port = process.env.PORT || 8081;
app.listen(port, () => {
  console.log(`TripDetails running on :${port}`);
});