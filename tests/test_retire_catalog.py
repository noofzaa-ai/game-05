import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retire_catalog', Path(__file__).resolve().parents[1] / 'tools/backend/retire_catalog.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RetirementValidationTests(unittest.TestCase):
    def setUp(self):
        self.before = {'rng_state': '123', 'profile': {'beta_kit_version': 1, 'bonus_stash_slots': 155, 'name': 'Hero', 'appearance': {}, 'loadout': {'equipped': {'weapon:0': {'id': 'beta-v1-blade_02'}}}, 'stash': {'items': [{'id': 'beta-v1-blade_02', 'item_id': 'blade_02'}, {'id': 'earned-1', 'item_id': 'blade_02'}], 'capacity': 195, 'gold': '250', 'materials': {'ore': 4}}}}
        self.after = copy.deepcopy(self.before)
        self.after['profile']['beta_kit_version'] = 2
        self.after['profile']['bonus_stash_slots'] = 0
        self.after['profile']['stash']['capacity'] = 40
        self.after['profile']['stash']['items'].pop(0)
    def test_valid_retirement(self):
        original = copy.deepcopy(self.before)
        self.assertEqual(module.validate(self.before, self.after), 1)
        self.assertEqual(self.before, original)
    def test_equipped_preserved(self):
        self.after['profile']['loadout']['equipped'] = {}
        with self.assertRaises(ValueError): module.validate(self.before, self.after)
    def test_earned_preserved(self):
        self.after['profile']['stash']['items'] = []
        with self.assertRaises(ValueError): module.validate(self.before, self.after)
    def test_balances_preserved(self):
        self.after['profile']['stash']['gold'] = '0'
        with self.assertRaises(ValueError): module.validate(self.before, self.after)
    def test_rng_preserved(self):
        self.after['rng_state'] = '124'
        with self.assertRaises(ValueError): module.validate(self.before, self.after)
    def test_version_required(self):
        self.after['profile']['beta_kit_version'] = 1
        with self.assertRaises(ValueError): module.validate(self.before, self.after)
