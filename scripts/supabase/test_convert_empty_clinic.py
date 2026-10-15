import os
import unittest
from unittest.mock import patch
import convert_empty_clinic as conversion


class ConversionTests(unittest.TestCase):
    def test_invalid_scope_rejected(self):
        with self.assertRaises(ValueError):
            conversion.statement('owner@example.test', 'invalid', 'Clinic')

    def test_literals_are_escaped(self):
        sql = conversion.statement('owner@example.test', '83524f18-f928-405d-aa3a-8d0766103eaa', "Owner's clinic")
        self.assertIn("'Owner''s clinic'", sql)
        self.assertNotIn('__CLINIC_ID__', sql)

    def test_confirmation_required_before_network(self):
        with patch.dict(os.environ, {'CONVERSION_CONFIRMATION': ''}), patch.object(conversion, 'query') as query:
            with self.assertRaises(SystemExit):
                conversion.main()
            query.assert_not_called()

    def test_incomplete_postcheck_fails(self):
        env = {'CONVERSION_CONFIRMATION': 'ELIMINAR_SOLO_CLINICA_VACIA_Y_CONSERVAR_CUENTA', 'CONVERSION_EMAIL': 'owner@example.test', 'CONVERSION_CLINIC_ID': '83524f18-f928-405d-aa3a-8d0766103eaa', 'CONVERSION_CLINIC_NAME': 'Clinic'}
        with patch.dict(os.environ, env), patch.object(conversion, 'query', side_effect=[[], [{'clinic_removed': False}]]):
            with self.assertRaises(SystemExit):
                conversion.main()


if __name__ == '__main__':
    unittest.main()
