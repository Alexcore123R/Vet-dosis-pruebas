import unittest
from integration_remote_rehearsal import rehearse


def state():
    return {'receipt':False,'module_contract':False,'rotation':False,
            'beta_closed':True,'permissions_dormant':True,'patients':2,'routines':{'test':'hash'}}


class RemoteTrialTests(unittest.TestCase):
    def test_only_rollback_is_sent_and_final_state_is_compared(self):
        calls=[]
        def read(sql):
            calls.append(sql)
            return [{'state':state()}] if len(calls)!=2 else []
        self.assertTrue(rehearse(read)['server_rollback_trial_passed'])
        self.assertTrue(calls[1].endswith('rollback;\n'))
        self.assertNotIn('\ncommit;', calls[1])

    def test_partial_or_open_installation_is_rejected_before_trial(self):
        for key in ('receipt','module_contract','rotation','beta_closed','permissions_dormant'):
            current=state();current[key]=not current[key]
            calls=[]
            def read(sql):
                calls.append(sql)
                return [{'state':current}]
            with self.assertRaises(ValueError):rehearse(read)
            self.assertEqual(len(calls),1)

    def test_changed_verification_is_never_reported_as_success(self):
        calls=[]
        def read(sql):
            calls.append(sql)
            current=state()
            if len(calls)==3:current['patients']=3
            return [{'state':current}]
        with self.assertRaises(ValueError):rehearse(read)


if __name__ == '__main__':
    unittest.main()
