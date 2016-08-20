// Two body representation
// TODO: plug the huge number of potential memory leaks
#include <iostream>
#include <stdio.h>
#include <cmath> //abs
#include <math.h>
#include <vector>

#define PI 3.14159265
using namespace std;


vector<double> cross_product (vector<double> u, vector<double> v)
{
    double i = (u[1]*v[2]) - (u[2]*v[1]);
    double j = (u[2]*v[0]) - (u[0]*v[2]);
    double k = (u[0]*v[1]) - (u[1]*v[0]);
    return vector<double> {i , j, k};
}

double dot_product (vector<double> u, vector<double> v)
{
    return (u[0]*v[0])+(u[1]*v[1])+(u[2]*v[2]);
}

double norm (vector<double> u)
{
    return sqrt(dot_product(u, u));
}

vector<double> vec_scale (double f, vector<double> u)
{
    return vector<double> {f*u[0], f*u[1], f*u[2]};
}

vector<double> vec_shift (double f, vector<double> u)
{
    return vector<double> {f+u[0], f+u[1], f+u[2]};
}

vector<double> vec_add (vector<double> a, vector<double> b)
{
    return vector<double> {a[0]+b[0], a[1]+b[1], a[2]+b[2]};
}

void dump_vector(string const &title, vector<double> dat)
{
    cout<<title;
    printf(" : [%f, %f, %f]\n", dat[0], dat[1], dat[2]);
}

double c2(double psi)
{
    double res;
    if (psi > 1.0)
    {
        res = (1.0 - cos(sqrt(psi))) / psi;
    }
    else if (psi < -1.0)
    {
        res = (cosh(sqrt(-1*psi))-1.0) / (-1.0 * psi);
    }
    else
    {
        res = .5;
        double delta = (-1.0*psi) / tgamma(5);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = pow((-1.0*psi), k)/tgamma(2*k + 3);
        }
    }
    return res;
}

double c3(double psi)
{
    double res;
    if (psi > 1.0)
    {
        res =  (sqrt(psi) - sin(sqrt(psi))) / pow(psi, 1.5);
    }
    else if (psi < -1.0)
    {
        res = (sinh(sqrt(-1.0*psi)) - sqrt(-1.0*psi)) / (-1.0 * psi * sqrt(-1.0*psi));
    }
    else
    {
        res = 1.0 / 6.0;
        double delta = (-1.0 * psi) / tgamma(6);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = pow((-1.0*psi), k) / tgamma(2*k+4);
        }
    }
    return res;
}

class EarthOrbit
{
    int numiter = 35;
    double rtol = 1e-10;
    double k = 398600.4415;
    void rv2coe();
  public:
    vector<double> r;
    vector<double> v;
    double ecc;
    double p;
    double a;
    double inc;
    double raan;
    double argp;
    double nu;
    EarthOrbit(vector<double>, vector<double>);
    void propagate(double);
    void maneuver(vector<double>);
};

EarthOrbit::EarthOrbit (vector<double> r_in, vector<double> v_in){
    r = r_in;
    v = v_in;
    rv2coe();
}

void EarthOrbit::rv2coe()
{
    vector<double> z = {0., 0., 1.0};
    vector<double> h = cross_product(r, v);
    double norm_h = norm(h);
    vector<double> n = vec_scale(1.0/norm_h, cross_product(z, h));
    vector<double> e = vec_scale((1.0/k), vec_add(vec_scale(dot_product(v, v)-(k/norm(r)), r), vec_scale(-1.0*dot_product(r, v),v)));
    ecc = norm(e);
    p = dot_product(h, h) / k;
    a = p / (1.0 - pow(ecc, 2.0));
    inc = acos(h[2]/norm(h));
    raan = atan2(n[1], n[0]);
    argp = atan2(dot_product(e, vec_scale(1.0/norm_h, cross_product(h, n))), dot_product(e, n));
    nu = atan2(dot_product(r, vec_scale(1.0/norm_h, cross_product(h, e))), dot_product(r, e));
}

void EarthOrbit::propagate(double tof)
{
    //Compute Lagrange coefficients
    vector<double> r0 = r;
    vector<double> v0 = v;
    double dot_r0v0 = dot_product(r0, v0);
    double norm_r0 = norm(r0);
    double sqrt_mu = pow(k, .5);
    double alpha = (2/norm_r0)-(dot_product(v0, v0)/k);
    double xi_new;
    if (alpha > 0)
    {
        //Elliptical Orbit
        xi_new = sqrt_mu * tof * alpha;
    }
    else if (alpha < 0)
    {
        //Hyperbolic Orbit
        xi_new = sqrt(-1.0/alpha)*log((-2.0*k*alpha*tof)/(dot_r0v0+(sqrt(-1.0*k/alpha)*(1.0-norm_r0*alpha))));
    }
    else
    {
        //Parabolic Orbit
        xi_new = sqrt_mu * tof / norm_r0;
    }
    //Newton-Raphson iteration on the Kepler equation
    int count = 0;
    double xi;
    double psi;
    double c2_psi;
    double c3_psi;
    double norm_r;
    while (count < numiter)
    {
        xi = xi_new;
        psi = xi * xi * alpha;
        c2_psi = c2(psi);
        c3_psi = c3(psi);
        norm_r = (xi*xi*c2_psi +
                dot_r0v0/sqrt_mu*xi * (1.0-psi*c3_psi) +
                norm_r0 * (1.0 - psi * c2_psi));
        xi_new = xi + (sqrt_mu * tof - xi*xi*xi*c3_psi -
                dot_r0v0 / sqrt_mu * xi * xi * c2_psi -
                norm_r0 * xi * (1 - psi * c3_psi)) / norm_r;
        if (abs((xi_new - xi)/xi_new) < rtol || abs( xi_new - xi) < rtol)
        {
            break;
        }
        else
        {
            count ++;
        }
        // TODO: raise error when too many iterations reached
    }
    double f = 1.0 - pow(xi, 2) / norm_r0 * c2_psi;
    double g = tof - pow(xi, 3) / sqrt_mu * c3_psi;
    double gdot = 1.0 - pow(xi, 2) / norm_r * c2_psi;
    double fdot = sqrt_mu / (norm_r * norm_r0) * xi * (psi * c3_psi - 1.0);
    r = vec_add(vec_scale(f, r0), vec_scale(g, v0));
    v = vec_add(vec_scale(fdot, r0), vec_scale(gdot, v0));
}

void EarthOrbit::maneuver(vector<double> dv){
    propagate(dv[3]);
    vector<double> v0 = v;
    v = vec_add(v0, dv);
    rv2coe();
}

int main()
{
    vector<double> r = {-6045., -3490., 2500.};
    vector<double> v = {-3.457, 6.618, 2.533};
    EarthOrbit ship_orbit (r, v);
    printf ("Semi-major Axis: %f\n", ship_orbit.a);
    printf ("Eccentricity: %f\n", ship_orbit.ecc);
    printf ("Inclination: %f\n", ship_orbit.inc);
    printf ("Right Ascension of Ascending Node: %f\n", ship_orbit.raan);
    printf ("Argument of Pericenter: %f\n", ship_orbit.argp);
    printf ("True anamoly: %f\n", ship_orbit.nu);
    ship_orbit.propagate(5.0);
    dump_vector("R", ship_orbit.r);
    dump_vector("V", ship_orbit.v);
    vector<double> dv = {.05, 0.0, 0.0, 10.0};
    ship_orbit.maneuver(dv);
    dump_vector("R", ship_orbit.r);
    dump_vector("V", ship_orbit.v);
    printf ("Semi-major Axis: %f\n", ship_orbit.a);
    printf ("Eccentricity: %f\n", ship_orbit.ecc);
    printf ("Inclination: %f\n", ship_orbit.inc);
    printf ("Right Ascension of Ascending Node: %f\n", ship_orbit.raan);
    printf ("Argument of Pericenter: %f\n", ship_orbit.argp);
    printf ("True anamoly: %f\n", ship_orbit.nu);

}