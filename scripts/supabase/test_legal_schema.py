import hashlib
import os
import unittest
from unittest.mock import patch
import legal_schema as operator

STATE={'beta_ready':True,'permissions_ready':True,'beta_closed':True,'acceptance_table':False,'acceptance_rpc':False,'platform_list':False,'platform_revoke':False}

class LegalOperatorTests(unittest.TestCase):
    def rejected(self,state,confirmation='PREPARAR_TERMINOS_SIN_PUBLICAR'):
        with patch.dict(os.environ,{'LEGAL_ACTION':'prepare','LEGAL_CONFIRMATION':confirmation}),patch.object(operator,'query',return_value=[state]) as query:
            with self.assertRaises(SystemExit):operator.main()
            self.assertEqual(query.call_count,1)

    def test_requires_explicit_preparation_confirmation(self):
        self.rejected(STATE,'')

    def test_cannot_change_open_beta(self):
        self.rejected({**STATE,'beta_closed':False})

    def test_cannot_overwrite_partial_schema(self):
        self.rejected({**STATE,'acceptance_table':True})

    def test_inspection_is_read_only(self):
        with patch.dict(os.environ,{'LEGAL_ACTION':'inspect'}),patch.object(operator,'query',return_value=[STATE]) as query:
            operator.main();self.assertEqual(query.call_count,1)

    def test_source_version_and_digest_are_exact(self):
        data=operator.load_draft()
        self.assertEqual(data['version'],'1')
        self.assertEqual(data['state'],'draft')
        self.assertIn('Versión 1 (borrador)',data['content'])
        self.assertEqual(data['hash'],hashlib.sha256(data['content'].encode('utf-8')).hexdigest())

    def test_draft_import_never_publishes_and_escapes_text(self):
        data=operator.load_draft();data['content']="Owner's legal text"
        sql=operator.draft_sql(data)
        self.assertIn("Owner''s legal text",sql)
        self.assertIn('published_terms_cannot_be_replaced_by_draft',sql)
        self.assertNotIn('published=true',sql)
        self.assertNotIn('terms_acceptances',sql)
