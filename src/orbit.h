#ifndef ORBIT_H
#define ORBIT_H
#include <cmath>

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
    double DV = .015;

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
    void relative_maneuver(glm::vec3, double);
    void dump_state();
};
#endif
