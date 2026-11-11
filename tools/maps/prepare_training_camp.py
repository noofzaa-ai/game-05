#!/usr/bin/env python3
"""Derived camp clearing; preserve supplied camp and farm level groups."""
from pathlib import Path
import shutil
from split_farm_trees import split_farm_trees
root=Path(__file__).resolve().parents[2]
source=root/'art/maps/camp_hub/camp_hub.glb'
destination=root/'art/maps/camp_hub/camp_training.glb'
shutil.copyfile(source,destination)
split_farm_trees(destination,True,rect=(-26,-10,-3,12),flat=(-25,-11,-2,11),group_name='TrainingBoundaryTrees')
