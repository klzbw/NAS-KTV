# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
# Vendored LDDC logger — headless stub.
# The upstream logger hard-depends on PySide6 (Qt message handler + on-disk file logging).
# In the NASKTV headless downloader we replace it with a stdlib logging adapter that
# exposes the same `logger` attribute (debug/info/warning/error/critical/log/exception)
# used across the LDDC lyrics modules.

import logging

logger = logging.getLogger("LDDC")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("[%(levelname)s] %(name)s: %(message)s"))
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
