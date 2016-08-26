#!/usr/bin/env python2.7
import numpy as np
from astropy import units as u

from poliastro.bodies import Earth, Sun
from poliastro.twobody import State
from poliastro.maneuver import Maneuver

r = [-6045, -3490, 2500] * u.km
v = [-3.457, 6.618, 2.533] * u.km / u.s

ss = State.from_vectors(Earth, r, v)
print(ss.a)
print(ss.ecc)
print(ss.inc)
print(ss.raan)
print(ss.argp)
print(ss.nu)
print(ss.e_vec)
print("OTHER")
ss_i = ss.propagate(time_of_flight=5*u.s)
print(ss_i.rv())
man = Maneuver( (10*u.s, [.05, 0, 0]*u.km / u.s))
ss_f = ss_i.apply_maneuver(man)
print(ss_f.rv())
print(ss_f.a)
print(ss_f.ecc)
print(ss_f.inc)
print(ss_f.raan)
print(ss_f.argp)
print(ss_f.nu)
