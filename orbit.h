#ifndef ORBIT_H
#define ORBIT_H
#include <iostream>
#include <stdio.h>
#include <math.h>
using namespace std;

struct vec3D {
    double i;
    double j;
    double k;
};

struct vec4D {
    double i;
    double j;
    double k;
    double t;
};

class EarthOrbit
{
    int numiter = 35;
    double rtol = 1e-10;
    double k = 398600.4415;
    void rv2coe();
    double DV = .05;
    double DT = 10.0;

    vec4D forward = {DV, 0, 0, DT};
    vec4D backward = {-1.0*DV, 0, 0, DT};
    vec4D left = {0, DV, 0, DT};
    vec4D right = {0, -1.0*DV, 0, DT};
  public:
    vec3D r;
    vec3D v;
    double r_p;
    double r_a;
    double ecc;
    double p;
    double a;
    double b;
    double inc;
    double raan;
    double argp;
    double nu;
    double norm_r;
    EarthOrbit(vec3D, vec3D);
    ~EarthOrbit();
    void propagate(double);
    void maneuver(vec4D&);
    void relative_maneuver(vec4D&);
    void dump_state();
    void goForward();
    void goLeft();
    void goRight();
    void goBackward();
};
#endif
