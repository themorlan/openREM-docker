Initial experimental development build of OpenREM 1.0.0dev0 in Docker.

**NOT READY FOR USE!**

Instructions
============

* Download and extract https://bitbucket.org/openrem/docker/get/master.zip and open a shell (command window) in the
  new folder
* Customise any variables in `.env.prod`, `.env.prod.db` and in the `environment` section of `orthanc_1`
  in `docker-compose.yml` as necessary. A full list of variables for Orthanc will be made available later.

Start the containers with:

`docker-compose up -d`

Get the database ready:

* `docker-compose exec openrem python manage.py makemigrations remapp --noinput`
* `docker-compose exec openrem python manage.py migrate --noinput`
* `docker-compose exec openrem python manage.py createsuperuser`
* `docker-compose exec openrem python manage.py collectstatic --noinput --clear`

Open a web browser and go to http://localhost/

(Although on my Windows host, Docker Toolbox uses IP 192.168.99.100 so I needed to go to http://192.168.99.100/
instead - maybe not an issue with Docker Desktop?)

