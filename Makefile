# Packaging for the Linux-cross-built Win32/emu client.
#
# `make package` zips build_shared/bin/release into a client-distributable
# archive, excluding everything private or useless to a Windows client:
#   - config/            login.db holds AutoLogin credentials; INIs are personal.
#                        Only config/MacroQuest_default.ini is shipped.
#   - *.pdb              debug symbols (~320M of the folder)
#   - Logs/, *.log       session logs and crash dumps
#   - mq-tray-helper     Linux ELF (wine SNI tray helper), inert on Windows
#   - .git*              lua/ and macros/ are git working copies
#   - random-named .exe  byte-identical MacroQuest.exe copies the loader makes;
#                        each install regenerates its own

RELEASE_DIR := build_shared/bin/release
STAGE_DIR   := build_shared/package-stage
PACKAGE     := build_shared/MacroQuest-win32-emu-$(shell date +%Y%m%d).zip

.PHONY: package
package:
	@test -d $(RELEASE_DIR) || { echo "error: $(RELEASE_DIR) not found - build first"; exit 1; }
	rm -rf $(STAGE_DIR)
	rsync -a \
		--exclude='*.pdb' \
		--exclude='*.log' \
		--exclude='/config/' \
		--exclude='/Logs/' \
		--exclude='/mq-tray-helper' \
		--exclude='.git*' \
		$(RELEASE_DIR)/ $(STAGE_DIR)/
	mkdir -p $(STAGE_DIR)/config
	cp $(RELEASE_DIR)/config/MacroQuest_default.ini $(STAGE_DIR)/config/
	for exe in $(STAGE_DIR)/*.exe; do \
		[ "$$exe" = "$(STAGE_DIR)/MacroQuest.exe" ] && continue; \
		if cmp -s "$$exe" "$(STAGE_DIR)/MacroQuest.exe"; then rm -v "$$exe"; fi; \
	done
	rm -f $(PACKAGE)
	cd $(STAGE_DIR) && zip -qr $(CURDIR)/$(PACKAGE) .
	rm -rf $(STAGE_DIR)
	@ls -lh $(PACKAGE)
