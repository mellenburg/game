#include <iostream>
#include <stdio.h>
#include <math.h>
#include <vector>
using namespace std;

class EarthOrbit
{
    int numiter = 35;
    double rtol = 1e-10;
    double k = 398600.4415;
    void rv2coe();
  public:
    vector<double> r;
    vector<double> v;
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
    EarthOrbit(vector<double>, vector<double>);
    void propagate(double);
    void maneuver(vector<double>);
    void relative_maneuver(vector<double> dv);
};
