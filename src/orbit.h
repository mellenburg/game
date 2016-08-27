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

double dot_product (vec3D&, vec3D&);

class EarthOrbit
{
    int numiter = 35;
    double rtol = 1e-10;
    double k = 398600.4415;
    void rv2coe();
    double DV = .015;

    vec3D forward = {DV, 0, 0};
    vec3D backward = {-1.0*DV, 0, 0};
    vec3D left = {0, DV, 0};
    vec3D right = {0, -1.0*DV, 0};
    vec3D up = {0, 0, DV};
    vec3D down = {0, 0, -1.0*DV};
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
    double norm_v;
    double period;
    EarthOrbit(vec3D&, vec3D&);
    ~EarthOrbit();
    void clone(EarthOrbit&);
    void propagate(double);
    void maneuver(vec4D&);
    void relative_maneuver(vec4D&);
    void relative_maneuver(vec3D&, double);
    void dump_state();
    void goForward(double);
    void goLeft(double);
    void goRight(double);
    void goBackward(double);
    void goUp(double);
    void goDown(double);
};
#endif
