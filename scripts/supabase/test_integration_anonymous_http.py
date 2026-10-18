import unittest
from integration_anonymous_http import probe


class AnonymousHttpTests(unittest.TestCase):
    def test_denials_are_only_accepted_after_key_validation(self):
        calls=[]
        def send(path,data=None):
            calls.append((path,data))
            return (200,{}) if data is None else (401,{'code':'42501'})
        report=probe(send)
        self.assertEqual(len(report['anonymous_rpc_probes']),3)
        self.assertEqual(calls[0],('/auth/v1/settings',None))

    def test_bad_key_missing_rpc_or_success_is_not_permission_evidence(self):
        for response in ((404,{'code':'PGRST202'}),(200,{}),(401,{'message':'invalid API key'})):
            def send(path,data=None):return (200,{}) if data is None else response
            with self.assertRaises(ValueError):probe(send)
        with self.assertRaises(ValueError):probe(lambda *args:(401,{}))


if __name__=='__main__':unittest.main()
