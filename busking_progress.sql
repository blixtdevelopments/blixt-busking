CREATE TABLE IF NOT EXISTS `busking_progress` (
    `citizenid` VARCHAR(50) NOT NULL,
    `xp` INT NOT NULL DEFAULT 0,
    `level` INT NOT NULL DEFAULT 0,
    `songs_completed` INT NOT NULL DEFAULT 0,
    `best_crowd` INT NOT NULL DEFAULT 0,
    `achievements` LONGTEXT NULL,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
