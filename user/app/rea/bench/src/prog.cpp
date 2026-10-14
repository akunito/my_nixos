// M1 corpus program (C++): STL containers, algorithms, strings, exceptions, virtuals.
#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Shape {
  virtual ~Shape() = default;
  virtual double area() const = 0;
  virtual std::string name() const = 0;
};
struct Rect : Shape {
  double w, h;
  Rect(double a, double b) : w(a), h(b) {}
  double area() const override { return w * h; }
  std::string name() const override { return "rect"; }
};
struct Circle : Shape {
  double r;
  explicit Circle(double a) : r(a) {}
  double area() const override { return 3.14159265358979 * r * r; }
  std::string name() const override { return "circle"; }
};

static std::unique_ptr<Shape> parse(const std::string &line) {
  std::istringstream in(line);
  std::string kind;
  in >> kind;
  if (kind == "rect") { double w, h; in >> w >> h; return std::make_unique<Rect>(w, h); }
  if (kind == "circle") { double r; in >> r; return std::make_unique<Circle>(r); }
  throw std::runtime_error("unknown shape: " + kind);
}

int main() {
  std::vector<std::unique_ptr<Shape>> shapes;
  std::map<std::string, double> totals;
  std::string line;
  while (std::getline(std::cin, line)) {
    try { shapes.push_back(parse(line)); } catch (const std::exception &e) { std::cerr << e.what() << '\n'; }
  }
  std::sort(shapes.begin(), shapes.end(), [](auto &a, auto &b) { return a->area() < b->area(); });
  for (auto &s : shapes) totals[s->name()] += s->area();
  for (auto &[k, v] : totals) std::cout << k << ' ' << v << '\n';
}
