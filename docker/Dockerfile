# Static web page served by nginx.
#
# Pinned to a digest-able minor tag rather than :latest so a rebuild months from
# now produces the same image — "latest" would silently change the base OS under
# you and is the usual reason a working image stops working.
FROM nginx:1.27-alpine

# nginx:alpine already runs as root only for the master process and drops to
# nginx for workers, and listens on 80. Nothing to change there.
COPY index.html /usr/share/nginx/html/index.html

# Documents intent; does not publish the port by itself.
EXPOSE 80

