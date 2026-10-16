import hashlib
import os
import unittest
from unittest.mock import patch
import privacy_schema as operator

STATE = dict(beta_closed=True, terms_ready=True, notice_table=False, terms_binding=False, receipt_binding=False, accept_rpc=False, enroll_rpc=False)

class PrivacyOperatorTests(unittest.TestCase):
    def test_exact_source(self):
        data=operator.load_privacy()
        self.assertEqual(data['hash'],hashlib.sha256(data['content'].encode()).hexdigest())
        self.assertEqual(data['version'],'1')

    def test_inspection_cannot_write(self):
        with patch.dict(os.environ,{'PRIVACY_ACTION':'inspect'}),patch.object(operator,'query',return_value=[STATE]) as query:
            operator.main();self.assertEqual(query.call_count,1)

    def test_rejects_unapproved_open_or_partial_state(self):
        for state,confirmation in [(STATE,''),({**STATE,'beta_closed':False},'PREPARAR_AVISO_SIN_PUBLICAR'),({**STATE,'notice_table':True},'PREPARAR_AVISO_SIN_PUBLICAR')]:
            with self.subTest(state=state,confirmation=confirmation),patch.dict(os.environ,{'PRIVACY_ACTION':'prepare','PRIVACY_CONFIRMATION':confirmation}),patch.object(operator,'query',return_value=[state]) as query:
                with self.assertRaises(SystemExit):operator.main()
                self.assertEqual(query.call_count,1)

    def test_binding_never_publishes_or_fabricates_receipts(self):
        sql=operator.binding_sql(operator.load_draft(),operator.load_privacy())
        self.assertIn('published_privacy_cannot_be_replaced_by_draft',sql)
        self.assertNotIn('published=true',sql)
        self.assertNotIn('terms_acceptances',sql)
        self.assertNotIn('beta_enrollments',sql)

    def test_preparation_is_atomic_and_verifies_unpublished_binding(self):
        checked={'beta_closed':True,'exact_unpublished_binding':True}
        with patch.dict(os.environ,{'PRIVACY_ACTION':'prepare','PRIVACY_CONFIRMATION':'PREPARAR_AVISO_SIN_PUBLICAR'}),patch.object(operator,'query',side_effect=[[STATE],[],[checked]]) as query:
            operator.main()
            self.assertEqual(query.call_count,3)
            sql=query.call_args_list[1].args[0]
            self.assertTrue(sql.startswith('begin;'))
            self.assertIn('select 1 from private.beta_policy for update',sql)
            self.assertIn('create table private.beta_privacy_notices',sql)
            self.assertIn('lock table private.beta_terms in share row exclusive mode',sql)
            self.assertIn('published_privacy_cannot_be_replaced_by_draft',sql)
            self.assertTrue(sql.endswith('commit;'))
