ALTER TABLE user_consents ADD COLUMN reason TEXT CHECK(reason IS NULL OR char_length(reason)<=1000);
