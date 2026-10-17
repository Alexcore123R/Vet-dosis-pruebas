import unittest
from unittest.mock import Mock

from integration_storage_inventory import inspect


class StorageInventoryTests(unittest.TestCase):
    def test_counts_never_claim_binary_backup_or_export_paths(self):
        read=Mock(return_value=[{'buckets':3,'objects':2,'known_bytes':100,'unknown_size_objects':0}])
        report=inspect(read)
        self.assertFalse(report['binary_backup_created'])
        self.assertEqual(report['objects'],2)
        self.assertTrue(read.call_args.args[0].startswith('select'))

    def test_incomplete_or_invalid_inventory_fails_closed(self):
        for rows in ([],[{}],[{'buckets':3,'objects':-1,'known_bytes':100,'unknown_size_objects':0}]):
            with self.assertRaises(ValueError):
                inspect(Mock(return_value=rows))


if __name__=='__main__':
    unittest.main()
