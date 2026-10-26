# Faster training and concurrent hatch

Owner request: 4 payments per second at the previous payment value, with no hatch pause. Config now awards 16 base hits per second. ShopService no longer writes a hatch block; TrainingService ignores the retired block attribute. Training cadence retains fractional time without accumulating missed rewards after a stall.

Validation: 892 Luau tests, 6 runner self-tests, 133 Python tests; Selene, StyLua and Rojo passed. Integrated actual ShopService/TrainingService mock-runtime test observed 24 payments over 6 seconds while buying two eggs, with the training start time unchanged. This is automated runtime evidence, not physical-device proof.

Studio TEST Edit model verified against 172 mapped instances including 153 exact source SHA256 hashes. Place version before publication is 103. Owner stated checks were sufficient and requested no more computer control. No further native UI actions were performed. AssetService SavePlaceAsync from Edit returned: Game:SavePlace can only be called from a server script, aborting save function. Publication of this candidate is NOT confirmed. Studio is left in Edit mode with the verified changes ready for direct publication. Historical v103 proof remains in the prior report.

The faster rate changes progression: economy gate currently fails gym1 timing, final gym timing and gym1/gym2 rebirth targets. See tuning/report.md. No targets or prices were changed to mask failures. Physical mobile, impaired-network and persistent save/re-entry proof remain pending.
