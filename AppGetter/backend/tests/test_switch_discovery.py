from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from backend.switch_discovery import analyze_installer, extract_switch_tokens


class SwitchDiscoveryTests(unittest.TestCase):
    def test_extract_switch_tokens_from_text(self) -> None:
        text = "Use /VERYSILENT /SUPPRESSMSGBOXES for unattended deployment."
        tokens = extract_switch_tokens(text)
        self.assertIn("/VERYSILENT", tokens)
        self.assertIn("/SUPPRESSMSGBOXES", tokens)

    def test_msi_installer_has_known_switches(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".msi", delete=False) as temp_file:
            temp_path = Path(temp_file.name)
            temp_file.write(b"MSI")

        try:
            result = analyze_installer(temp_path)
            self.assertEqual(result["status"], "known")
            self.assertIn("/quiet", [token.lower() for token in result["knownSwitches"]])
        finally:
            temp_path.unlink(missing_ok=True)

    def test_exe_static_analysis_discovers_switches(self) -> None:
        binary_blob = b"Inno Setup Setup Data .... /VERYSILENT /NORESTART /SUPPRESSMSGBOXES ...."
        with tempfile.NamedTemporaryFile(suffix=".exe", delete=False) as temp_file:
            temp_path = Path(temp_file.name)
            temp_file.write(binary_blob)

        try:
            result = analyze_installer(temp_path)
            self.assertIn(result["status"], {"known", "discovered"})
            recommended = [value.upper() for value in result["recommendedSwitches"]]
            self.assertIn("/VERYSILENT", recommended)
        finally:
            temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
