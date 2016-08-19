// Two body representation
#include <iostream>
#include <stdio.h>
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

vector<double> rv_coe (vector<double> r, vector<double> v)
{
    double k = 398600.4415;
    vector<double> z = {0., 0., 1.0};
    vector<double> h = cross_product(r, v);
    double norm_h = norm(h);
    vector<double> n = vec_scale(1.0/norm_h, cross_product(z, h));
    vector<double> e = vec_scale((1.0/k), vec_add(vec_scale(dot_product(v, v)-(k/norm(r)), r), vec_scale(-1.0*dot_product(r, v),v)));
    double ecc = norm(e);
    double p = dot_product(h, h) / k;
    double a = p / (1.0 - pow(ecc, 2.0));
    double inc = acos(h[2]/norm(h));
    double raan = atan2(n[1], n[0]);
    double argp = atan2(dot_product(e, vec_scale(1.0/norm_h, cross_product(h, n))), dot_product(e, n));
    double nu = atan2(dot_product(r, vec_scale(1.0/norm_h, cross_product(h, e))), dot_product(r, e));
    return vector<double> { a, ecc, inc, raan, argp, nu};
}

vector<double> earth_orbit()
{
    vector<double> r = {-6045., -3490., 2500.};
    vector<double> v = {-3.457, 6.618, 2.533};
    return rv_coe(r, v);
}

/*
int main()
{
    vector<double> r = {-6045., -3490., 2500.};
    vector<double> v = {-3.457, 6.618, 2.533};
    vector<double>orbital_coe = rv_coe(r, v);
    printf ("Semi-major Axis: %f\n", orbital_coe[0]);
    printf ("Eccentricity: %f\n", orbital_coe[1]);
    printf ("Inclination: %f\n", orbital_coe[2]);
    printf ("Right Ascension of Ascending Node: %f\n", orbital_coe[3]);
    printf ("Argument of Pericenter: %f\n", orbital_coe[4]);
    printf ("True anomoly: %f\n", orbital_coe[5]);
}
*/
