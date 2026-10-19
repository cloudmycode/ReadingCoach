package services

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"
)

// Every mutation of a user's reward ledger holds this row lock first.
func (s *ReadingService) lockReadingUser(ctx context.Context, tx *sql.Tx, user int, now time.Time) (string, string, error) {
	loc, _ := time.LoadLocation("Asia/Shanghai")
	if _, err := tx.ExecContext(ctx, `INSERT INTO reading_accounts(user_id,starts_on,timezone) VALUES(?,?,?) ON DUPLICATE KEY UPDATE user_id=reading_accounts.user_id`, user, now.In(loc).Format("2006-01-02"), loc.String()); err != nil {
		return "", "", err
	}
	var start, zone string
	err := tx.QueryRowContext(ctx, `SELECT starts_on,timezone FROM reading_accounts WHERE user_id=? FOR UPDATE`, user).Scan(&start, &zone)
	return start, zone, err
}
func (s *ReadingService) currentCycle(ctx context.Context, tx *sql.Tx, user int, now time.Time) (*ReadingCycle, error) {
	anchor, zone, err := s.lockReadingUser(ctx, tx, user, now)
	if err != nil {
		return nil, err
	}
	loc, err := time.LoadLocation(zone)
	if err != nil {
		return nil, err
	}
	start, end, err := readingCycleDates(anchor, now.In(loc).Format("2006-01-02"), loc)
	if err != nil {
		return nil, err
	}
	_, err = tx.ExecContext(ctx, `INSERT IGNORE INTO reading_cycles(user_id,starts_on,ends_on,timezone,rules_json) VALUES(?,?,?,?,?)`, user, start, end, zone, readingJSON(readingTiers))
	if err != nil {
		return nil, err
	}
	var id int64
	if err = tx.QueryRowContext(ctx, `SELECT id FROM reading_cycles WHERE user_id=? AND starts_on=?`, user, start).Scan(&id); err != nil {
		return nil, err
	}
	return s.cycle(ctx, tx, user, id, now)
}
func (s *ReadingService) cycle(ctx context.Context, q readingDB, user int, id int64, now time.Time) (*ReadingCycle, error) {
	c := &ReadingCycle{ID: id, CompletedDays: []string{}}
	var rules string
	var settled sql.NullInt64
	err := q.QueryRowContext(ctx, `SELECT starts_on,ends_on,timezone,rules_json,settled_at FROM reading_cycles WHERE id=? AND user_id=?`, id, user).Scan(&c.StartsOn, &c.EndsOn, &c.Timezone, &rules, &settled)
	if err != nil {
		return nil, readingMissing(err)
	}
	if err = json.Unmarshal([]byte(rules), &c.Tiers); err != nil {
		return nil, err
	}
	rows, err := q.QueryContext(ctx, `SELECT completed_on FROM reading_days WHERE cycle_id=? AND user_id=? ORDER BY completed_on`, id, user)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var day string
		if err = rows.Scan(&day); err != nil {
			rows.Close()
			return nil, err
		}
		c.CompletedDays = append(c.CompletedDays, day)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if err = q.QueryRowContext(ctx, `SELECT COUNT(*) FROM reading_attempts WHERE cycle_id=? AND status='pending'`, id).Scan(&c.PendingAttempts); err != nil {
		return nil, err
	}
	for _, tier := range c.Tiers {
		if len(c.CompletedDays) >= tier.Days {
			c.Tier = tier
		}
	}
	loc, err := time.LoadLocation(c.Timezone)
	if err != nil {
		return nil, err
	}
	c.Today = now.In(loc).Format("2006-01-02")
	c.Status = "active"
	if settled.Valid {
		c.Status = "settled"
	} else if c.Today > c.EndsOn {
		c.Status = "settling"
	}
	return c, nil
}

// Only the highest tier is issued, once, after the period ends (or all 30 days pass).
func (s *ReadingService) settleCycle(ctx context.Context, tx *sql.Tx, user int, id int64, now time.Time) error {
	c, err := s.cycle(ctx, tx, user, id, now)
	if err != nil {
		return err
	}
	if c.Status == "settled" || c.PendingAttempts > 0 || (c.Status == "active" && len(c.CompletedDays) < 30) {
		return nil
	}
	if c.Tier.Stars > 0 {
		_, err = tx.ExecContext(ctx, `INSERT IGNORE INTO reading_vouchers(user_id,cycle_id,stars,completed_days,amount_fen,issued_at) VALUES(?,?,?,?,?,?)`, user, id, c.Tier.Stars, len(c.CompletedDays), c.Tier.AmountFen, now.Unix())
		if err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `UPDATE reading_cycles SET settled_at=? WHERE id=? AND settled_at IS NULL`, now.Unix(), id)
	return err
}
func (s *ReadingService) recordReadingPass(ctx context.Context, tx *sql.Tx, p *readingPaper, attempt, cycle int64, day string) error {
	var exists int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM reading_passes WHERE user_id=? AND content_hash IN (?,?)`, p.UserID, readingHash(p.Source), p.RootHash).Scan(&exists); err != nil {
		return err
	}
	for _, hash := range []string{readingHash(p.Source), p.RootHash} {
		if _, err := tx.ExecContext(ctx, `INSERT IGNORE INTO reading_passes(user_id,content_hash,attempt_id) VALUES(?,?,?)`, p.UserID, hash, attempt); err != nil {
			return err
		}
	}
	if exists > 0 {
		return nil
	}
	_, err := tx.ExecContext(ctx, `INSERT IGNORE INTO reading_days(user_id,completed_on,cycle_id,attempt_id) VALUES(?,?,?,?)`, p.UserID, day, cycle, attempt)
	return err
}
func (s *ReadingService) Challenge(ctx context.Context, user int) (*ReadingCycle, error) {
	var c *ReadingCycle
	err := s.transaction(ctx, func(tx *sql.Tx) error {
		var e error
		c, e = s.currentCycle(ctx, tx, user, s.now())
		if e != nil {
			return e
		}
		if e = s.settleCycle(ctx, tx, user, c.ID, s.now()); e != nil {
			return e
		}
		c, e = s.cycle(ctx, tx, user, c.ID, s.now())
		return e
	})
	return c, err
}
func (s *ReadingService) Cycles(ctx context.Context, user int) ([]ReadingCycle, error) {

	out := []ReadingCycle{}
	err := s.transaction(ctx, func(tx *sql.Tx) error {
		if _, err := s.currentCycle(ctx, tx, user, s.now()); err != nil {
			return err
		}
		rows, err := tx.QueryContext(ctx, `SELECT id FROM reading_cycles WHERE user_id=? ORDER BY starts_on DESC LIMIT 24`, user)
		if err != nil {
			return err
		}
		var ids []int64
		for rows.Next() {
			var id int64
			if err = rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			ids = append(ids, id)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return err
		}
		for _, id := range ids {
			if err = s.settleCycle(ctx, tx, user, id, s.now()); err != nil {
				return err
			}
			c, e := s.cycle(ctx, tx, user, id, s.now())
			if e != nil {
				return e
			}
			out = append(out, *c)
		}
		return nil
	})
	return out, err
}

// SettleDue is also run periodically: opening the app isn't required to issue a voucher.
func (s *ReadingService) SettleDue(ctx context.Context) error {
	rows, err := s.db.QueryContext(ctx, `SELECT id,user_id FROM reading_cycles WHERE settled_at IS NULL AND ends_on<=?`, s.now().UTC().Add(24*time.Hour).Format("2006-01-02"))
	if err != nil {
		return err
	}
	type pending struct {
		id   int64
		user int
	}
	var list []pending
	for rows.Next() {
		var p pending
		if err = rows.Scan(&p.id, &p.user); err != nil {
			rows.Close()
			return err
		}
		list = append(list, p)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, p := range list {
		if err = s.transaction(ctx, func(tx *sql.Tx) error {
			if _, _, e := s.lockReadingUser(ctx, tx, p.user, s.now()); e != nil {
				return e
			}
			return s.settleCycle(ctx, tx, p.user, p.id, s.now())
		}); err != nil {
			return err
		}
	}
	return nil
}
func scanReadingVoucher(row interface{ Scan(...any) error }) (ReadingVoucher, error) {
	var v ReadingVoucher
	var redeemed sql.NullInt64
	err := row.Scan(&v.ID, &v.CycleID, &v.Stars, &v.CompletedDays, &v.AmountFen, &v.IssuedAt, &redeemed)
	v.Status = "available"
	if redeemed.Valid {
		v.Status = "redeemed"
		v.RedeemedAt = &redeemed.Int64
	}
	return v, err
}

const readingVoucherColumns = `id,cycle_id,stars,completed_days,amount_fen,issued_at,redeemed_at`

func (s *ReadingService) Vouchers(ctx context.Context, user int, status string, limit, offset int) ([]ReadingVoucher, error) {
	if limit < 1 || limit > 100 || offset < 0 {
		return nil, ErrReadingInvalid
	}
	where := ""
	switch status {
	case "available":
		where = " AND redeemed_at IS NULL"
	case "redeemed":
		where = " AND redeemed_at IS NOT NULL"
	case "":
	default:
		return nil, ErrReadingInvalid
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+readingVoucherColumns+` FROM reading_vouchers WHERE user_id=?`+where+` ORDER BY issued_at DESC,id DESC LIMIT ? OFFSET ?`, user, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ReadingVoucher{}
	for rows.Next() {
		v, e := scanReadingVoucher(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
func (s *ReadingService) Redeem(ctx context.Context, user int, id int64) (*ReadingVoucher, error) {
	var v ReadingVoucher
	err := s.transaction(ctx, func(tx *sql.Tx) error {
		_, e := tx.ExecContext(ctx, `UPDATE reading_vouchers SET redeemed_at=COALESCE(redeemed_at,?) WHERE id=? AND user_id=?`, s.now().Unix(), id, user)
		if e != nil {
			return e
		}
		v, e = scanReadingVoucher(tx.QueryRowContext(ctx, `SELECT `+readingVoucherColumns+` FROM reading_vouchers WHERE id=? AND user_id=?`, id, user))
		return readingMissing(e)
	})
	return &v, err
}
