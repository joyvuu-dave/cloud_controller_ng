#!/bin/bash

###############################################################################
# Simple Demo Runner - Checks Prerequisites First
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "MySQL FK Constraint Fix Demo"
echo "=========================================="
echo ""

# Check if Docker/Colima is running
echo "Checking Docker..."
if docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker is running${NC}"
else
    echo -e "${RED}✗ Docker is not running${NC}"
    echo ""
    echo "Please start Docker first:"
    echo ""
    echo "  If using Colima:"
    echo "    colima start"
    echo ""
    echo "  If using Docker Desktop:"
    echo "    open -a Docker"
    echo ""
    echo "Then run this script again."
    echo ""
    echo "Alternatively, see QUICK_START.md for manual testing options."
    exit 1
fi

# Check if MySQL container is running
echo "Checking MySQL container..."
if docker ps | grep -q mysql; then
    echo -e "${GREEN}✓ MySQL container is running${NC}"
else
    echo -e "${YELLOW}⚠ MySQL container not running${NC}"
    echo "Starting MySQL with docker-compose..."
    docker-compose up -d mysql
    echo "Waiting 15 seconds for MySQL to start..."
    sleep 15
fi

# Test MySQL connection
echo "Testing MySQL connection..."
if docker exec mysql mysqladmin ping -h localhost -uroot -psupersecret > /dev/null 2>&1; then
    echo -e "${GREEN}✓ MySQL is responding${NC}"
else
    echo -e "${RED}✗ Cannot connect to MySQL${NC}"
    echo "Try: docker-compose restart mysql"
    exit 1
fi

echo ""
echo "=========================================="
echo "Running Tests"
echo "=========================================="
echo ""

# Run the test
DB=mysql \
MYSQL_CONNECTION_PREFIX="mysql2://root:supersecret@127.0.0.1:3306" \
bundle exec rspec spec/unit/lib/mysql_truncate_with_fk_spec.rb \
    --format documentation \
    --color

echo ""
echo "=========================================="
echo "Test Complete!"
echo "=========================================="
echo ""
echo "What the tests proved:"
echo "  ✓ dataset.truncate FAILS with FK constraints (bug exists)"
echo "  ✓ db.synchronize + FK handling WORKS (fix is correct)"
echo ""

