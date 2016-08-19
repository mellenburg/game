#!/usr/bin/env python2.7
import numpy as np
from astropy import units as u

from poliastro.bodies import Earth, Sun
from poliastro.twobody import State

r = [-6045, -3490, 2500] * u.km
v = [-3.457, 6.618, 2.533] * u.km / u.s

ss = State.from_vectors(Earth, r, v)
print(ss.a)
print(ss.ecc)
print(ss.inc)
print(ss.raan)
print(ss.argp)
print(ss.nu)
ss_i = ss.propagate(time_of_flight=5*u.s)
print(ss_i.rv())
