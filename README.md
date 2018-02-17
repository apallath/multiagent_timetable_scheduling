# Multiagent system for solving a simplified version of University Timetable Scheduling

This is an implementation of a multiagent system for timetable scheduling, in [NetLogo](https://ccl.northwestern.edu/netlogo/) (. Different breeds of agents play the role of different stake-holders in the problem, and simulate the negotiation that normally occurs in offline course-scheduling to arrive at an optimal schedule.

In this model, I make the following assumptions:

- All lectures are of the same time interval
- All lectures are of the same type
- There is no bottleneck in terms of rooms (we do not need to account for rooms during scheduling - just the time slots)

I've used the largest degree heuristic and simulated annealing to solve part of the problem. Currently, this handles intra-department scheduling. I still have to implement the function where individual department schedules are patched together to create a global schedule, while minimizing the number of clashes.

# Structure of input files:

courses.txt

num_departments
num_courses
\[course\_id department\_id]

professors_and_courses.txt

num_professors
\[department\_id list\_courses]

students_and_courses.txt

num_students
\[department\_id list\_own\_dept\_courses list\_other\_dept\_courses]
